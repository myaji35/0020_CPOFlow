# frozen_string_literal: true

module Gmail
  # Gmail API 응답의 body.data는 SDK 버전에 따라:
  #   - 구(≤ 0.46): base64url 인코딩된 ASCII 문자열
  #   - 신(≥ 0.47): 이미 디코딩된 바이너리(Encoding=ASCII-8BIT)
  # 양쪽을 투명하게 처리하여 UTF-8 문자열로 반환한다.
  module BodyDecoder
    module_function

    # Gmail API가 돌려준 body.data / attachment body.data 를 안전 디코딩.
    # nil, blank는 ""로 반환.
    def decode(data)
      return "" if data.nil? || data.empty?

      raw =
        if looks_like_base64url?(data)
          begin
            ::Base64.urlsafe_decode64(data)
          rescue ArgumentError
            data
          end
        else
          data
        end

      raw.force_encoding("UTF-8").encode("UTF-8", invalid: :replace, undef: :replace)
    end

    # Attachment용 — 항상 바이너리(ASCII-8BIT)로 반환.
    def decode_binary(data)
      return nil if data.nil? || data.empty?

      if looks_like_base64url?(data)
        begin
          return ::Base64.urlsafe_decode64(data)
        rescue ArgumentError
          # fallthrough
        end
      end
      data
    end

    # base64url 가능성 휴리스틱:
    # - ASCII/UTF-8 인코딩이고
    # - 공백·제어문자가 거의 없으며
    # - [A-Za-z0-9_\-=] 비율이 98% 이상
    def looks_like_base64url?(data)
      return false unless data.is_a?(String)
      return false unless [ Encoding::US_ASCII, Encoding::UTF_8 ].include?(data.encoding)

      sample = data.byteslice(0, 512) || data
      return false if sample.empty?
      valid = sample.each_byte.count { |b|
        (b >= 0x30 && b <= 0x39) || # 0-9
        (b >= 0x41 && b <= 0x5A) || # A-Z
        (b >= 0x61 && b <= 0x7A) || # a-z
        b == 0x2D || b == 0x5F || b == 0x3D # - _ =
      }
      (valid.to_f / sample.bytesize) >= 0.98
    end
  end
end
