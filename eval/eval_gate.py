#!/usr/bin/env python3
"""
Eval gate for the RAG orchestrator.
Runs known questions, checks answers contain expected keywords.
Exits 1 (blocks deploy) if the pass rate is below PASS_THRESHOLD.
"""
import json
import os
import sys
from pathlib import Path

from azure.identity import DefaultAzureCredential
from azure.keyvault.secrets import SecretClient
from azure.search.documents import SearchClient
from azure.search.documents.models import VectorizedQuery
from openai import OpenAI

KEY_VAULT_URI = "https://llmopslearn-kv.vault.azure.net"
SEARCH_ENDPOINT = "https://llmopslearn-search.search.windows.net"
INDEX_NAME = "documents-index"
TOP_K = 3
# Override via EVAL_PASS_THRESHOLD env var (e.g. 0.75 to lower the bar)
PASS_THRESHOLD = float(os.environ.get("EVAL_PASS_THRESHOLD", "0.8"))

QUESTIONS_FILE = Path(__file__).parent / "questions.json"


def get_answer(openai_client, search_client, embedding_deployment, chat_deployment, question):
    embedding = openai_client.embeddings.create(
        input=question, model=embedding_deployment
    ).data[0].embedding

    results = search_client.search(
        search_text=None,
        vector_queries=[VectorizedQuery(
            vector=embedding, k_nearest_neighbors=TOP_K, fields="content_vector"
        )],
        select=["content"],
    )
    chunks = [r["content"] for r in results]
    if not chunks:
        return None

    context = "\n\n".join(chunks)
    prompt = (
        "Answer the question using ONLY the context below. "
        "If the context doesn't contain the answer, say you don't have enough information.\n\n"
        f"Context:\n{context}\n\nQuestion: {question}\n\nAnswer:"
    )
    response = openai_client.chat.completions.create(
        model=chat_deployment,
        messages=[
            {"role": "system", "content": "You are a helpful assistant that answers questions strictly from the provided context."},
            {"role": "user", "content": prompt},
        ],
    )
    return response.choices[0].message.content


def main():
    questions = json.loads(QUESTIONS_FILE.read_text())

    credential = DefaultAzureCredential()
    kv = SecretClient(vault_url=KEY_VAULT_URI, credential=credential)

    embedding_deployment = kv.get_secret("embedding-deployment-name").value
    chat_deployment = kv.get_secret("chat-deployment-name").value
    litellm_master_key = kv.get_secret("litellm-master-key").value

    litellm_url = os.environ["LITELLM_INTERNAL_URL"]
    openai_client = OpenAI(
        api_key=litellm_master_key,
        base_url=f"https://{litellm_url}/v1",
    )
    search_client = SearchClient(
        endpoint=SEARCH_ENDPOINT,
        index_name=INDEX_NAME,
        credential=credential,
    )

    passed = 0
    for item in questions:
        question = item["question"]
        keywords = [kw.lower() for kw in item["expected_keywords"]]

        answer = get_answer(
            openai_client, search_client, embedding_deployment, chat_deployment, question
        )

        if answer is None:
            print(f"FAIL [no chunks retrieved]: {question}")
            continue

        answer_lower = answer.lower()
        missing = [kw for kw in keywords if kw not in answer_lower]
        if not missing:
            passed += 1
            print(f"PASS: {question}")
        else:
            print(f"FAIL: {question}")
            print(f"  missing keywords : {missing}")
            print(f"  answer (preview) : {answer[:200]!r}")

    total = len(questions)
    score = passed / total if total else 0.0
    print(f"\nScore: {passed}/{total} ({score:.0%}) — threshold {PASS_THRESHOLD:.0%}")

    if score < PASS_THRESHOLD:
        print("GATE FAILED — deploy blocked")
        sys.exit(1)

    print("GATE PASSED — proceeding to deploy")


if __name__ == "__main__":
    main()
