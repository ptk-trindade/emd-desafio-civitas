BEGIN

CREATE OR REPLACE TEMP TABLE radares_confiaveis AS
with radar_placa_tipo as (
    select distinct camera_numero, placa, tipoveiculo
    from `rj-cetrio.desafio.readings_2024_06`
),

-- Apenas 1 radar marcou o veiculo como sendo daquele tipo
um_erro as (
    select placa, tipoveiculo, count(*) as qtd
    from radar_placa_tipo
    group by placa, tipoveiculo
    having qtd = 1
),

-- Placas vistas por + de 10 radares
placa_muito_vista as (
    select placa, count(*) as qtd
    from radar_placa_tipo
    group by placa
    having qtd > 10
),

-- Quantos veiculos passaram por essa camera
veiculos_por_camera AS (
    select camera_numero, count(distinct placa) as qtd_registros
    from radar_placa_tipo rpt
    group by camera_numero
)

select 
    rpt.camera_numero, 
    count(ue.placa) as qtd_inconsistencias,
    vpc.qtd_registros,
    1 - (count(ue.placa)/vpc.qtd_registros) AS acuracia
from radar_placa_tipo rpt

left join um_erro ue
    on rpt.placa = ue.placa
    and rpt.tipoveiculo = ue.tipoveiculo

inner join veiculos_por_camera vpc
    on rpt.camera_numero = vpc.camera_numero
where rpt.placa in (select placa from placa_muito_vista)
group by rpt.camera_numero, vpc.qtd_registros
having acuracia > 0.99;


CREATE OR REPLACE TEMP TABLE possiveis_clonagens AS
-- Limpa algumas linhas e ajeita algumas colunas
with readings_filtered as (
  select rd.placa,
    rd.tipoveiculo,
    rd.camera_numero,
    rd.datahora AS datahora,
    ABS(TIMESTAMP_DIFF(rd.datahora, rd.datahora_captura, SECOND)) AS erro_datahora,
    IF(rd.camera_longitude < 0, rd.camera_longitude, -rd.camera_longitude) AS longitude,
    rd.camera_latitude AS latitude,
    rd.velocidade,
    (rc.camera_numero is not null) AS tipo_confiavel
  FROM rj-cetrio.desafio.readings_2024_06 rd
  left join radares_confiaveis rc
    on rd.camera_numero = rc.camera_numero
  -- WHERE camera_latitude != 0.0 -- Não precisamos filtrá-los aqui
),

-- Define velocidade máxima esperada para aquele veiculo
velocidade_veiculo as (
  select placa, GREATEST(150, MAX(velocidade) + 30) AS velocidade_maxima
  from rj-cetrio.desafio.readings_2024_06
  group by placa
),

-- Conta em quantos tipos diferentes uma mesma placa aparece
placa_tipos as (
  SELECT placa, COUNT(DISTINCT tipoveiculo) AS qtd_tipos
  FROM `rj-cetrio.desafio.readings_2024_06`
  GROUP BY placa
),

		
-- Considerando apenas os radares confiáveis (para determinar o tipo), conta em quantos tipos diferentes uma mesma placa aparece
placa_tipos_confiavel as (
  SELECT placa, COUNT(DISTINCT tipoveiculo) AS qtd_tipos_confiavel,
  FROM `rj-cetrio.desafio.readings_2024_06` rd
  inner join radares_confiaveis rc
    on rd.camera_numero = rc.camera_numero
  GROUP BY placa
),

-- Identifica o deslocamento de uma placa entre 2 radares
movimentacao_placa as (
  select inicio.placa, 
    (inicio.tipo_confiavel AND fim.tipo_confiavel) tipo_confiavel,
    GREATEST(inicio.erro_datahora, fim.erro_datahora) AS erro_datahora,

    inicio.tipoveiculo tipo_inicial,
    inicio.velocidade velocidade_inicial,
    inicio.camera_numero camera_inicial,
    inicio.datahora datahora_inicial, 
    ST_GEOGPOINT(inicio.longitude, inicio.latitude) posicao_inicial,
    
    fim.tipoveiculo tipo_final,
    fim.velocidade velocidade_final,
    fim.camera_numero camera_final,
    fim.datahora datahora_final,
    ST_GEOGPOINT(fim.longitude, fim.latitude) posicao_final

  from readings_filtered inicio
  inner join readings_filtered fim
    on inicio.placa = fim.placa
    and inicio.datahora < fim.datahora

),

-- Calcula o tempo, distância e vel. média do deslocamento
velocidade_movimentacao as (
  select mp.placa,
    camera_inicial,
    camera_final,
    posicao_inicial, 
    posicao_final, 
    datahora_inicial, 
    datahora_final,
    velocidade_inicial,
    velocidade_final,
    (tipo_inicial != tipo_final) tipos_diferentes,
    tipo_confiavel,

    ST_DISTANCE(posicao_inicial, posicao_final) distancia,
    TIMESTAMP_DIFF(datahora_final, datahora_inicial, SECOND) tempo,

    3.6 * ST_DISTANCE(posicao_inicial, posicao_final)/(TIMESTAMP_DIFF(datahora_final, datahora_inicial, SECOND) + GREATEST(30, erro_datahora)) velocidade_media, --  em km/h. 30s de folga permitem um pequeno erro de localização e/ou relógio

    vv.velocidade_maxima
  from movimentacao_placa mp
  inner join velocidade_veiculo vv
    on mp.placa = vv.placa
  
  where TIMESTAMP_DIFF(datahora_final, datahora_inicial, SECOND) < 300 -- 5 min
),

-- Cria CTE com a camera e vel. média do deslocamento que passou por esta
cameras as (
    SELECT
      placa,
      camera_inicial AS camera,
      posicao_inicial AS posicao,
      velocidade_media,
      velocidade_maxima,
      tipos_diferentes,
      tipo_confiavel,
      camera_final AS camera2
    FROM velocidade_movimentacao
  UNION ALL
    SELECT
      placa,
      camera_final AS camera,
      posicao_final AS posicao,
      velocidade_media,
      velocidade_maxima,
      tipos_diferentes,
      tipo_confiavel,
      camera_inicial AS camera2
    FROM velocidade_movimentacao
),

-- Identifica radares com muitas vel. médias acima do esperado
cameras_validas as (
  SELECT 
    camera,
    COUNTIF(velocidade_media < velocidade_maxima OR tipos_diferentes) / count(*) AS porcentagem_coerente,
  FROM cameras
  group by camera
  having porcentagem_coerente > 0.7
)

-- Seleciona a placa, a quantidade de tipos que ela possui e quantas vezes esta placa se "teleportou"
SELECT 
  c.placa,
  pt.qtd_tipos,
  ptc.qtd_tipos_confiavel,

  COUNTIF(camera in (select camera from cameras_validas) AND camera2 in (select camera from cameras_validas)) as qtd_inconsistencias_deslocamento,

  COUNTIF(c.tipos_diferentes AND c.tipo_confiavel) AS mudanca_tipo_confiavel,
  COUNTIF(c.tipos_diferentes) AS mudanca_tipo_total
FROM cameras c
inner join placa_tipos pt
  on c.placa = pt.placa
left join placa_tipos_confiavel ptc
  on c.placa = ptc.placa
where velocidade_media > velocidade_maxima
group by placa, qtd_tipos, qtd_tipos_confiavel;


with provavel_clonagem as (
    select *,
    (qtd_tipos_confiavel - 1) / 3
    + qtd_inconsistencias_deslocamento / 10
    + mudanca_tipo_confiavel / 4
    + mudanca_tipo_total / 8
    AS pontos_clonagem
    from possiveis_clonagens
)
select * from provavel_clonagem
where pontos_clonagem > 1.0
;

END