# Desafio CIVITAS - EMD

Repositório de instrução para o desafio técnico para a vaga na Prefeitura do Rio de Janeiro

## Descrição do desafio

Neste desafio, você deverá utilizar os dados de uma tabela BigQuery que contém leituras de radar do município do Rio de Janeiro. A tabela já contém dados com as leituras realizadas por cada radar.

O objetivo é fazer uma análise exploratória dos dados, identificar inconsistências, além de identificar placas de veículos que foram possivelmente clonadas, usando as informações disponíveis. 

### Acesso aos Dados no BigQuery

Para acessar os dados disponíveis na tabela BigQuery `rj-cetrio.desafio.readings_2024_06`, é necessário informar o e-mail que será utilizado para as consultas. Após a liberação, você pode seguir nosso tutorial de [como acessar dados do BigQuery](https://docs.dados.rio/tutoriais/como-acessar-dados/#acessando-dados-via-bigquery). Os dados têm o seguinte esquema:

| Coluna           | Tipo       | Descrição                                 |
|------------------|------------|-------------------------------------------|
| datahora         | TIMESTAMP  | Data e hora da leitura                    |
| datahora_captura | TIMESTAMP  | Data e hora da captura pelo radar         |
| placa            | BYTES      | Placa do veículo capturado                |
| empresa          | STRING     | Empresa do veículo                        |
| tipoveiculo      | STRING     | Tipo do veículo                           |
| velocidade       | INTEGER    | Velocidade do veículo                     |
| camera_numero    | STRING     | Número identificador da câmera            |
| camera_latitude  | FLOAT      | Latitude da câmera                        |
| camera_longitude | FLOAT      | Longitude da câmera                       |


### Requisitos

1. **Queries SQL:**
    - Análise exploratória dos dados, incluindo as inconsistências e queries utilizadas.
    - Query SQL que identifique e retone possíveis placas clonadas.

2. **Documentação e Apresentação:**
    - Documente o processo e explique a lógica utilizada para identificar as placas clonadas.
    - Esteja preparado para apresentar sua solução, explicando como a idealizou.

## O que iremos avaliar

- **Completude:** A solução proposta atende a todos os requisitos do desafio?
- **Simplicidade:** A solução proposta é simples e direta? É fácil de entender e trabalhar?
- **Organização:** A solução proposta é organizada e bem documentada? É fácil de navegar e encontrar o que se procura?
- **Criatividade:** A solução proposta é criativa? Apresenta uma abordagem inovadora para o problema proposto?
- **Boas práticas:** A solução proposta segue boas práticas de SQL?

## Atenção

- A solução deste desafio deve ser publicada em um fork deste repositório no GitHub.
- Você deve ser capaz de apresentar sua solução, explicando como a idealizou, caso seja aprovado(a) para a próxima etapa.

## Links de referência / utilidades

- Documentação [BigQuery](https://cloud.google.com/bigquery/docs)
- [Acessando dados via BigQuery](https://docs.dados.rio/tutoriais/como-acessar-dados/#acessando-dados-via-bigquery)

## Dúvidas?

Fale conosco pelo e-mail que foi utilizado para o envio deste desafio.
