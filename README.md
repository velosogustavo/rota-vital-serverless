# Rota Vital · Guia de transporte serverless

Atividade individual 1 (Serverless) · Infraestrutura de Software · ADS · CESAR School · 2026.2
Aluno(a): **Gustavo Rafael Renaux Veloso**

Função HTTP que recebe uma requisição de bolsas de sangue do Rota Vital (`POST /guias`) e devolve a guia de transporte. Roda no AWS Lambda, emulado localmente pelo **AWS SAM CLI** com Docker.

**Caminho escolhido: A (AWS SAM CLI local).** Não precisa de conta AWS.

**Repositório:** https://github.com/velosogustavo/rota-vital-serverless

## Estrutura

```
template.yaml            # função, API POST /guias, Timeout 3 s, 128 MB
hello_world/app.py       # handler lambda_handler
events/pedido.json       # evento API Gateway (gerado com sam local generate-event)
events/pedido-demorado.json
events/pedido-invalido.json
scripts/roteiro.sh       # roda os Passos 3, 4 e 5 e grava as saídas em evidencias/
tests/test_handler.py    # testes do handler sem Docker
evidencias/              # prints e saídas dos comandos
```

### Diferença em relação ao código do enunciado

O evento gerado por `sam local generate-event` vem com o body em **base64** (`"isBase64Encoded": true`). Com o código original, `json.loads` falhava nesse caso. O handler decodifica o body quando esse campo é verdadeiro. Ele também devolve 400 para um JSON inválido, em vez de 500. O resto segue o enunciado: contador global, `demorar` com `sleep(5)` e status 201.

## Como rodar

Pré-requisitos: Docker Desktop aberto e AWS SAM CLI (`sam --version`). No Windows, use Git Bash ou WSL.

```bash
git clone https://github.com/velosogustavo/rota-vital-serverless.git && cd rota-vital-serverless
python -m unittest discover tests -v      # opcional: testa o handler sem Docker
```

**Ajustes para rodar no Windows (Git Bash), feitos no `scripts/roteiro.sh`:**

- **`sam build --use-container`:** a minha máquina tem Python 3.13 e o template usa `python3.12`, e o `sam build` comum falhou com *"Failed to find a Python runtime containing pip on the PATH"*. Com `--use-container`, o build roda dentro da imagem Docker do Python 3.12. O runtime do template não mudou.
- **`sam` no Git Bash:** o instalador cria só o `sam.cmd`, e `alias` não vale dentro de script. Por isso, o roteiro define uma função `sam() { sam.cmd "$@"; }` quando `sam` não existe.
- **Parar o `start-api`:** no Git Bash, o `kill` não encerra o `python.exe` do SAM, e a porta 3000 continuava ocupada (os curls do passo seguinte iriam para o servidor antigo). Agora o `parar_api` usa `taskkill /T`, e o `subir_api` recusa subir se a porta já estiver em uso.
- O passo 5 também pode ser rodado em partes, com `timeout3` e `timeout10`.

Com o script, que grava tudo em `evidencias/`:

```bash
./scripts/roteiro.sh tudo        # ou: invoke | http | http-warm | timeout | timeout3 | timeout10
```

Ou passo a passo, à mão:

```bash
# Passo 3: evento
sam build --use-container
time sam local invoke -e events/pedido.json   # rodar 2x e anotar os tempos

# Passo 4: HTTP
sam local start-api
curl -X POST http://127.0.0.1:3000/guias -H "Content-Type: application/json" \
     -d '{"requisicaoId":"R-002","hospital":"H-Caruaru"}'      # 3x
# parar (Ctrl+C) e subir de novo com:
sam local start-api --warm-containers LAZY                     # e repetir os 3 curls

# Passo 5: limite de tempo
curl -X POST http://127.0.0.1:3000/guias -H "Content-Type: application/json" \
     -d '{"requisicaoId":"R-003","demorar":true}'
# trocar Timeout: 3 por Timeout: 10 no template.yaml, sam build --use-container, subir a API e repetir
```

Resposta esperada:

```json
{"guia": "G-R-001", "hospital": "H-Recife", "bolsas": ["O-NEG-0142"], "invocacaoNesteAmbiente": 1}
```

## Resultados

Medidos em 24/11/2026, Windows 11 + Docker Desktop 29.5.3 + SAM CLI 1.174.0, com `./scripts/roteiro.sh` no Git Bash.

| Experimento | Resultado | Evidência |
|---|---|---|
| `sam local invoke`, 1ª vez | **50,9 s** (`real`). O SAM não achou a imagem local e montou `python:3.12-rapid-x86_64`. Handler: 131,53 ms. HTTP 201. | [01-invoke.png](evidencias/01-invoke.png), [02-invoke-1.txt](evidencias/02-invoke-1.txt) |
| `sam local invoke`, 2ª vez | **16,2 s** (`real`). *"Local image is up-to-date"*, mas com um contêiner novo (outro `SAM_CONTAINER_ID`). Handler: 107,64 ms. | [01-invoke.png](evidencias/01-invoke.png), [02-invoke-2.txt](evidencias/02-invoke-2.txt) |
| 3 curls **sem** `--warm-containers` | `invocacaoNesteAmbiente` = **1, 1, 1**. Tempos: 4,64 s, 2,39 s e 2,41 s. | [02-http-sem-warm.png](evidencias/02-http-sem-warm.png), [03-curl-sem-warm.txt](evidencias/03-curl-sem-warm.txt) |
| 3 curls **com** `--warm-containers LAZY` | `invocacaoNesteAmbiente` = **1, 2, 3**. Tempos: 4,74 s, 1,10 s e 1,11 s. | [03-http-warm.png](evidencias/03-http-warm.png), [04-curl-warm.txt](evidencias/04-curl-warm.txt) |
| `demorar: true` com Timeout 3 s | **HTTP 502** `{"message":"Internal server error"}` após 10,7 s no curl (inclui subir o contêiner). Log: `Function 'HelloWorldFunction' timed out after 3 seconds`. | [04-timeout-3s.png](evidencias/04-timeout-3s.png), [05-start-api-timeout3.log](evidencias/05-start-api-timeout3.log) |
| `demorar: true` com Timeout 10 s | **HTTP 201** (`G-R-003`). A função durou **5138,54 ms**, e o curl levou 9,66 s no total (inclui subir o contêiner). | [05-timeout-10s.png](evidencias/05-timeout-10s.png), [06-start-api-timeout10.log](evidencias/06-start-api-timeout10.log) |

Prints e saídas completas em [`evidencias/`](evidencias/). Os testes (`python -m unittest discover tests -v`) passaram: 5 de 5. O `sam validate --lint` também passou.

## Respostas

**1. Por que a primeira invocação demorou mais que a segunda? O que acontece na fase de Init?**
Na primeira chamada não havia ambiente pronto, e esse é o *cold start*. Na fase de Init, o Lambda (aqui, o SAM com Docker) cria o ambiente de execução, inicia o runtime Python, carrega o código e roda tudo o que está fora do handler, como os imports e o `contador = 0`. Só depois chama o `lambda_handler`. No SAM local, a primeira vez ainda inclui baixar e montar a imagem Docker do runtime. Por isso a diferença local é maior que na nuvem. Na segunda chamada, a imagem já estava pronta (*"Local image is up-to-date"*), o que derrubou o tempo de 50,9 s para 16,2 s. Mas o `sam local invoke` **criou um contêiner novo** mesmo assim (outro `SAM_CONTAINER_ID`, `invocacaoNesteAmbiente` = 1 de novo), então ainda houve Init. O que sumiu foi só o preparo da imagem. O handler em si levou cerca de 0,1 s nas duas vezes (131 ms e 108 ms).

**2. O que o campo `invocacaoNesteAmbiente` mostrou com e sem `--warm-containers`? O que isso diz sobre estado em variável global?**
Sem a flag, o SAM cria um contêiner novo a cada requisição, e o campo veio sempre `1`. Com `--warm-containers LAZY`, o contêiner é reaproveitado, e o campo foi `1, 2, 3`. A variável global só sobrevive enquanto o mesmo ambiente estiver vivo. Na nuvem, o Lambda pode reaproveitar ou descartar o ambiente quando quiser e pode ter vários ambientes em paralelo, cada um com o seu contador. Então variável global serve como cache (conexão com banco, configuração), mas nunca para estado de negócio. Um número de guia ou uma contagem de pedidos tem que ficar num armazenamento externo, como DynamoDB, RDS ou Redis.

**3. O que aconteceu com `demorar = true`? Qual é o tempo máximo de uma execução no Lambda, e o que fazer com um trabalho mais longo?**
Com Timeout 3 s, a função foi interrompida no meio do `sleep(5)`. O log mostrou *timed out after 3 seconds*, e o curl recebeu 502 sem guia. Com Timeout 10 s e `sam build`, ela terminou em cerca de 5 s e devolveu 201. O máximo no Lambda é **900 s (15 minutos)**. Na integração com o API Gateway (REST) vale outro limite, de cerca de 29 s por padrão. Para um trabalho mais longo, dá para quebrar em etapas com **Step Functions**, responder logo e processar em segundo plano com uma **fila (SQS)**, ou rodar num contêiner sem esse limite (**ECS/Fargate** ou **AWS Batch**).

**4. Custo de 1 milhão de execuções com 128 MB e 100 ms (us-east-1, sem plano gratuito)**

```
Requisições: 1.000.000 × US$ 0,20 / 1.000.000          = US$ 0,20
Computação:  1.000.000 × 0,1 s × (128/1024) GB = 12.500 GB-s
             12.500 GB-s × US$ 0,0000166667             = US$ 0,2083
Total                                                   ≈ US$ 0,41
```

Usando 0,128 GB em vez de 128/1024 = 0,125 GB, dá 12.800 GB-s, US$ 0,2133 e um total de US$ 0,4133. A AWS cobra a memória em MB e converte com 1 GB = 1024 MB. Com o plano sempre gratuito (1 milhão de requisições e 400 mil GB-s por mês), esse volume custaria **US$ 0,00**.

**5. Em que parte do Rota Vital uma função assim faria sentido, e em qual não faria?**
Faz sentido no que é curto, sem estado e com tráfego irregular. Exemplos: gerar a guia de transporte quando chega uma requisição, validar um pedido, mandar notificação ao hospital ou ao motorista e reagir a eventos ("bolsa liberada" dispara a guia). O custo é zero quando não há pedido, e a função escala sozinha num pico. Não faz sentido no rastreamento contínuo da rota da viatura, com conexão aberta por WebSocket ou envio de GPS a cada segundo, nem em processamentos longos, como um relatório mensal pesado, que podem passar de 15 min. Também não serve para nada que dependa de estado em memória ou de latência baixa garantida, porque o cold start pesa num chamado urgente.

## Uso de IA

Utilizei o Claude (Anthropic) como apoio na estruturação do projeto, nos scripts, nos testes e na elaboração da documentação e das respostas, que são majoritariamente texto gerado pela ferramenta. A meu pedido, o Claude também executou os testes, o `sam validate --lint` e os passos do roteiro na minha máquina, adaptou o script ao Windows, capturou os prints em `evidencias/` e preencheu a tabela de resultados com os valores medidos. Conferi os resultados e os cálculos de custo.

Declarado conforme a PO-CESAR-021.

## Vídeo

Não enviado. As evidências da invocação com evento, da chamada HTTP e do erro de tempo limite estão nos prints em [`evidencias/`](evidencias/).
