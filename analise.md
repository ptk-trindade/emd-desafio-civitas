# Desafio CIVITAS - EMD

## Quantidade de registros
```sql
SELECT COUNT(*) AS total_registros
FROM `rj-cetrio.desafio.readings_2024_06`;
```
| qtd_registros |
| :-----: |
| 36.358.536 |


## Campos nulos

Foi identificado que, em aproximadamente 5% dos registros a coluna **datahora_captura** está nula. Já as outras colunas estão sempre todas preenchidas.

```sql
SELECT 
    COUNTIF(datahora IS NULL) AS dth_qtd_null,
    COUNTIF(datahora_captura IS NULL) AS dth_cap_qtd_null,
    COUNTIF(placa IS NULL) AS placa_qtd_null,
    COUNTIF(empresa IS NULL) AS emp_qtd_null,
    COUNTIF(tipoveiculo IS NULL) AS tipoveiculo_qtd_null,
    COUNTIF(velocidade IS NULL) AS vel_qtd_null,
    COUNTIF(camera_numero IS NULL) AS cam_num_qtd_null,
    COUNTIF(camera_latitude IS NULL) AS cam_lat_qtd_null,
    COUNTIF(camera_longitude IS NULL) AS cam_lon_qtd_null
FROM `rj-cetrio.desafio.readings_2024_06`;
```

| datahora_qtd_null | datahora_captura_qtd_null | placa_qtd_null | empresa_qtd_null | tipoveiculo_qtd_null | velocidade_qtd_null | cam_num_qtd_null | cam_lat_qtd_null | cam_lon_qtd_null |
| :-----: | :-----: | :-----: | :-----: | :-----: | :-----: | :-----: | :-----: | :-----: |
| 0 | 1816325 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |


## Inconsistências na geolocalização

Apesar de preenchidas, algumas coordenadas estão erradas.

```sql
select distinct camera_latitude, camera_longitude
from rj-cetrio.desafio.readings_2024_06
```

| camera_latitude | camera_longitude |
| :--------: | :-------: |
| -23.000612 | **43.334218** |
| **0.0** | **0.0** |
| -22.4850965 | -43.1223252 |
| . . . | . . . |

A primeira coordenada (com longitude positiva) se localiza no mar próximo a Madagascar. Se trocamos o sinal da longitude (de 43.334218 para -43.334218), temos um ponto bem no sinal da Av. das Américas, na Barra da Tijuca, onde é até possivel ver o radar pelo Google Street View.

Temos também alguns radares com coordenadas (0.0, 0.0). Para estes, não foi possível identificar a localização real e, por isso, serão desconsiderados nas análises de placas clonadas.

## Inconsistencias na relação entre Tipo e Placa

Era esperado que cada placa tivesse apenas um tipoveiculo, no entanto, muitas placas tem até os 4 tipos.

```sql
SELECT placa, COUNT(DISTINCT tipoveiculo) AS qtd_tipos
FROM `rj-cetrio.desafio.readings_2024_06`
GROUP BY placa
ORDER BY 2 DESC
```

| placa | qtd_tipos |
| :--------: | :-------: |
| 1wviF8QoAqJMH8RUcYZqBgQ= | 4 |
| YyHdLZrnlvDqbCDdu/aqCG4= | 4 |
| pIFAcqPMUSJBdj5LspWwC5I= | 4 |
| . . . | . . . |

Desenvolvendo a query um pouco mais, podemos saber quantas placas se repetem para 1, 2, 3 e 4 tipos.

```sql
SELECT qtd_tipos, COUNT(*) AS contagem
FROM (
    SELECT placa, COUNT(DISTINCT tipoveiculo) AS qtd_tipos
    FROM `rj-cetrio.desafio.readings_2024_06`
    GROUP BY placa
) AS placa_tipos_counts
GROUP BY qtd_tipos
ORDER BY qtd_tipos;

```

| qtd_tipos | contagem |
| :--------: | :-------: |
| 1 | 7542958 |
| 2 | 379316 |
| 3 | 54068 |
| 4 | 8268 |

Aqui, já temos um primeiro indício de clonagem de placas.

### Confiabilidade do tipoveiculo

Será que podemos confiar no tipo de veículo identificado pelo radar? O resultado da query abaixo nos mostra que nem sempre. Nela identificamos, para todos os veículos que passaram por mais de 10 radares diferentes, quando que apenas 1 desses radares aferiu que o veículo era de um determinado tipo específico.


```sql
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
-- having acuracia > 0.99;
```

| camera_numero | qtd_inconsistencias | qtd_registros | acuracia |
| :-----: | :-----: | :-----: | :-----: |
| rl6StfoCTA== | 1 | 2 | 0.5 |
| NUdKoaiF6w== | 16364 | 34683 | 0.52818 |
| utumbGcuJw== | 2910 | 9198 | 0.68362 |
| GvN9DIJZEw== | 1219 | 4478 | 0.72778 |
| ERs/joAaNg== | 412 | 1635 | 0.74801 |
| . . . | . . . | . . . | . . . |

Dos 1417 radares, 1165 tem uma acuracia acima de 99%. Vamos utilizar estes radares para identificar quais placas possuem mais de um tipo.


## Inconsistências Espaço x Tempo

Além de uma mesma placa com 2 diferentes tipos, um outro forte indício para duplicidade de placas é: Um veiculo passar por 2 (ou mais) radares muito distantes em um curto intervalo de tempo.

Estes indícios se tornam ainda maiores se combiandos, vamos supor. Uma placa passa em Copacabana com um tipo e, um minuto depois, passa no Recreio dos Bandeirantes com outro tipo. Neste caso, temos uma evidência ainda maior de que se trata de uma clonagem.

Na query abaixo é feito o seguinte processo:

readings_filtered: Selecionamos os radares e já deixamos marcados se eles são ou não confiáveis para determinar o tipo do veículo (conforme visto antes).

velocidade_veiculo: Determinamos a velocidade máxima para um determinado veiculo (150 km/h na maioria dos casos).

placa_tipos: Contamos para quantos tipos diferentes de veículos aquela placa existe

placa_tipos_confiavel: Igual ao processo anterior, porém considerando apenas os radares "confiáveis".

movimentacao_placa: Identificamos placas que passaram por 2 radares em um intervalo de tempo menor que 5 minutos.

velocidade_movimentacao: Com os dados da tabela anterior, calculamos a velocidade média deste deslocamento, a fim de detectar anomalias.

cameras: Utilizando os dados de velocidade média, criamos uma pequena tabela com inforamação sobre os radares.

cameras_validas: Identificamos câmeras que possuem muitas vezes velocidades médias acima do esperado e as descartamos. Estas provavelmente estão com suas coordenadas erradas.

Por fim, para cada placa temos:
- placa: A placa do veículo
- qtd_tipos: Por quantos tipos diferentes de veículos a placa foi vista (usando todos os radares)
- qtd_tipos_confiavel: Por quantos tipos diferentes de veículos a placa foi vista(considerando apenas radares confiáveis)
- qtd_inconsistencias_deslocamento: Quantas vezes o veículo se "teleportou" (nunca considerando os radares descartados por provável coordenadas erradas)
- mudanca_tipo_confiavel: Dessas vezes que o veículo se "teleportou", em quantas ele mudou de tipo (considerando apenas radares confiáveis)
- mudanca_tipo_confiavel: Dessas vezes que o veículo se "teleportou", em quantas ele mudou de tipo (usando todos os radares)
- pontos_clonagem: Uma pontuação pra determinar o quão provavel é desta placa ter sido clonada*

*Obs: Os pesos escolhidos são um pouco subjetivos e, conforme tivermos mais dados, podem sofrer mudanças.

Na query abaixo, foram encontrados 3056 suspeitas de placas clonadas.

```sql
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
```

| placa | qtd_tipos | qtd_tipos_confiavel | qtd_inconsistencias_deslocamento | mudanca_tipo_confiavel | mudanca_tipo_total | pontos_clonagem |
| :--------: | :-------: | :--------: | :-------: | :--------: | :-------: | :--------: |
| GaMACnoCD5GmG1nxKC4J1yg= | 2 | 2 | 0 | 2 | 2 | 1.08 |
| GtLDWaNtJJNYuT/hktXOE/Y= | 2 | 1 | 0 | 0 | 10 | 1.25 |
| hg9eTgy/rB4tnCcpG9nQi5o= | 2 | 2 | 0 | 2 | 2 | 1.08 |
| BcMqJNFwnZnV1jEc/fM+4ts= | 2 | 2 | 0 | 0 | 8 | 1.33 |
| 6NaYnHkNieqwQdix3sDljjg= | 2 | 1 | 0 | 0 | 10 | 1.25 |
| XvOU33yMKaIPWs1tnesKf/k= | 2 | 2 | 0 | 2 | 2 | 1.08 |
| Hsh3/c6XEVrxo/KfO+tvN30= | 2 | 2 | 0 | 2 | 2 | 1.08 |
| xsq6cAhviuN/5QAEIl+oMnk= | 2 | 2 | 0 | 2 | 2 | 1.08 |
| . . . | . . . | . . . | . . . | . . . | . . . | . . . 

