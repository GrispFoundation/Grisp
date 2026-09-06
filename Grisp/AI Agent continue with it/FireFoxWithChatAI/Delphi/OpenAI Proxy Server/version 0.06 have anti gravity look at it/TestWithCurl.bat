curl -s -X POST "http://127.0.0.1:8080/api/V1ChatCompletions" -H "Content-Type: application/json" -d "{\"model\":\"deepseek-chat\",\"messages\":[{\"role\":\"user\",\"content\":\"Hello from curl test\"}]}"
pause
