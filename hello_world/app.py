"""Rota Vital - função serverless que gera a guia de transporte de uma requisição.

Baseada no código do Passo 2 da atividade, com dois ajustes:
- decodifica o body quando vem em base64 (o evento criado por
  `sam local generate-event` vem com "isBase64Encoded": true);
- devolve 400 quando o body não é um JSON válido, em vez de quebrar com 500.
"""
import base64
import json
import time

contador = 0  # variável global: só sobrevive se o ambiente for reaproveitado

HEADERS = {"Content-Type": "application/json"}


def _ler_body(event):
    body = event.get("body") or "{}"
    if event.get("isBase64Encoded"):
        body = base64.b64decode(body).decode("utf-8")
    return json.loads(body)


def lambda_handler(event, context):
    global contador
    contador += 1

    try:
        pedido = _ler_body(event)
    except (ValueError, UnicodeDecodeError):
        return {"statusCode": 400, "headers": HEADERS,
                "body": json.dumps({"erro": "body precisa ser um JSON válido"})}

    if "requisicaoId" not in pedido:
        return {"statusCode": 400, "headers": HEADERS,
                "body": json.dumps({"erro": "requisicaoId obrigatório"})}

    if pedido.get("demorar"):
        time.sleep(5)  # passa do Timeout de 3 s do template

    guia = {"guia": "G-" + pedido["requisicaoId"],
            "hospital": pedido.get("hospital"),
            "bolsas": pedido.get("bolsas", []),
            "invocacaoNesteAmbiente": contador}
    return {"statusCode": 201, "headers": HEADERS, "body": json.dumps(guia)}
