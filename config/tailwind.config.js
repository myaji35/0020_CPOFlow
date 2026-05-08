// CPOFlow Tailwind config — production CDN(JIT) 제거. 인라인 layout config 그대로 이전.
// content 스캔 범위: 모든 ERB/HTML/JS/Ruby helper.
module.exports = {
  darkMode: 'class',
  content: [
    './public/*.html',
    './app/helpers/**/*.rb',
    './app/javascript/**/*.js',
    './app/views/**/*.{erb,haml,html,slim}',
    './app/components/**/*.{erb,html,rb}',
    './app/controllers/**/*.rb',
  ],
  theme: {
    extend: {
      colors: {
        // Legacy 토큰 — 기존 클래스 호환 유지 (점진 마이그레이션)
        primary:   { DEFAULT: '#1E3A5F', light: '#2D5282', dark: '#142844' },
        accent:    { DEFAULT: '#00A1E0', light: '#33b5e8' },
        danger:    '#D93025',
        warning:   '#F4A83A',
        success:   '#1E8E3E',
        // ── Redesign 토큰 (Phase 1) ──
        ink: {
          50:  '#fafbfc',
          75:  '#f5f6f8',
          100: '#eff1f4',
          150: '#e7eaee',
          200: '#dde1e6',
          300: '#c1c7d0',
          400: '#97a0ad',
          500: '#6b7585',
          600: '#4a5361',
          700: '#2b323d',
          800: '#1e242d',
          900: '#151a21',
          950: '#0c1014',
        },
        brand: {
          50:  '#e6f4f4',
          100: '#c7e7e8',
          200: '#99d2d4',
          400: '#3f9ba1',
          500: '#1f8389',
          600: '#166c72',
          700: '#11555a',
          900: '#072d31',
        },
        ok:     { 50: '#e9f6ed', 100: '#c6e7d0', 500: '#2e9856', 700: '#1f6f3f' },
        warn:   { 50: '#fdf2dc', 100: '#fbdea1', 500: '#d99a2a', 700: '#9a6a17' },
        dangerx:{ 50: '#fbe6e3', 100: '#f5c1b8', 500: '#c84431', 700: '#933123' },
        info:   { 50: '#e8edfb', 100: '#c3cef1', 500: '#3d5cc9', 700: '#293f93' },
        accentx:{ 50: '#f1e5fb', 500: '#8348c5' },
        stage: {
          new:     '#4a64d6',
          quo:     '#894fc4',
          pending: '#d0962e',
          po:      '#1a7079',
          deliver: '#2d8a4e',
          problem: '#c54431',
          grn:     '#2c7040',
          giveup:  '#7a7b82',
          done:    '#2b3e42',
        },
      },
      fontFamily: {
        sans: ['Inter Tight', 'Pretendard Variable', 'Pretendard', '-apple-system', 'Segoe UI', 'sans-serif'],
        mono: ['JetBrains Mono', 'SF Mono', 'ui-monospace', 'Menlo', 'monospace'],
      },
      borderRadius: {
        xs: '3px', sm: '5px', md: '7px', lg: '10px',
      },
      boxShadow: {
        'sh-1': '0 1px 2px rgba(12,16,20,.06), 0 1px 1px rgba(12,16,20,.04)',
        'sh-2': '0 2px 6px rgba(12,16,20,.06), 0 1px 2px rgba(12,16,20,.08)',
        'sh-3': '0 8px 24px rgba(12,16,20,.08), 0 2px 6px rgba(12,16,20,.06)',
        'sh-4': '0 24px 48px rgba(12,16,20,.14), 0 8px 16px rgba(12,16,20,.08)',
      },
    },
  },
  // 동적 클래스 보호 — bg-stage-* / text-stage-* 처럼 ERB에서 string interpolate 되는 것들.
  safelist: [
    { pattern: /^bg-(stage|brand|ink|ok|warn|dangerx|info|accentx)-(50|75|100|150|200|300|400|500|600|700|900|950|new|quo|pending|po|deliver|problem|grn|giveup|done)$/ },
    { pattern: /^text-(stage|brand|ink|ok|warn|dangerx|info|accentx)-(50|75|100|150|200|300|400|500|600|700|900|950|new|quo|pending|po|deliver|problem|grn|giveup|done)$/ },
    { pattern: /^border-(stage|brand|ink|ok|warn|dangerx|info|accentx)-(50|75|100|150|200|300|400|500|600|700|900|950|new|quo|pending|po|deliver|problem|grn|giveup|done)$/ },
  ],
}
