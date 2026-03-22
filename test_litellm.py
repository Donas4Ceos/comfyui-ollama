import json
import urllib.request
import urllib.parse

url = 'http://localhost:8000/v1/chat/completions'
data = {
    "model": "qwen2.5:0.5b",
    "messages": [
        {"role": "user", "content": "Hola Litellm! Eres un modelo de IA?"}
    ]
}

req = urllib.request.Request(
    url, 
    data=json.dumps(data).encode('utf-8'),
    headers={'Content-Type': 'application/json'}
)

try:
    with urllib.request.urlopen(req) as response:
        result = json.loads(response.read().decode('utf-8'))
        print("Response from LiteLLM:")
        print(result['choices'][0]['message']['content'])
except Exception as e:
    print(f"Error: {e}")
