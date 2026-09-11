import os

from locust import HttpUser, between, task


class VLLMUser(HttpUser):
    wait_time = between(1, 3)
    host = os.getenv("VLLM_BASE_URL", "http://localhost:8000")

    @task
    def chat_completion(self):
        headers = {"Content-Type": "application/json"}
        api_key = os.getenv("VLLM_API_KEY")
        if api_key:
            headers["Authorization"] = f"Bearer {api_key}"

        self.client.post(
            "/v1/chat/completions",
            headers=headers,
            json={
                "model": os.getenv("VLLM_MODEL", "Qwen/Qwen2.5-3B-Instruct"),
                "messages": [{"role": "user", "content": "Explain Kubernetes in one sentence."}],
                "max_tokens": 64,
                "temperature": 0.2,
            },
            name="/v1/chat/completions",
        )
