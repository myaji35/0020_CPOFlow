# lib/gemma.rb — Gemma 4 E4B 클라이언트 (로컬 ollama)
# 사용: Gemma.generate("보험 약관 요약: ...")

require "net/http"
require "json"
require "base64"
require "uri"

module Gemma
  BASE  = ENV.fetch("OLLAMA_BASE_URL", "http://localhost:11434")
  MODEL = ENV.fetch("OLLAMA_MODEL", "gemma4:e4b")

  module_function

  def generate(prompt:, images: nil, system: nil, temperature: 0.2, max_tokens: 2048)
    payload = {
      model: MODEL, prompt: prompt, stream: false,
      options: { temperature: temperature, num_predict: max_tokens }
    }
    payload[:system] = system if system
    payload[:images] = images if images

    uri = URI("#{BASE}/api/generate")
    http = Net::HTTP.new(uri.host, uri.port)
    http.read_timeout = ENV.fetch("OLLAMA_READ_TIMEOUT", "300").to_i
    http.open_timeout = 10
    req = Net::HTTP::Post.new(uri)
    req["Content-Type"] = "application/json"
    req.body = payload.to_json
    res = http.request(req)
    raise "Gemma #{res.code}: #{res.body}" unless res.is_a?(Net::HTTPSuccess)
    JSON.parse(res.body)["response"].to_s
  end

  def ocr(image_path, instruction: "이 이미지에서 텍스트를 그대로 추출. 레이아웃 순서 유지.")
    b64 = Base64.strict_encode64(File.binread(image_path))
    generate(prompt: instruction, images: [b64])
  end

  def parse_business_card(image_path)
    raw = ocr(image_path, instruction: '명함 이미지에서 JSON만 출력: {"name":..., "company":..., "title":..., "phone":..., "email":..., "address":...}. 없는 필드는 null. JSON 외 텍스트 금지.')
    match = raw[/\{[\s\S]*\}/]
    match ? JSON.parse(match) : {}
  end
end
