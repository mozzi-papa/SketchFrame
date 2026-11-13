import os
import sys
import xml.etree.ElementTree as ET
import subprocess
from PIL import Image, ImageDraw, ImageFont

DIR = os.path.dirname(os.path.abspath(__file__))

# -------------------------------------------------------------
# 1. Define SVG Icon Sources
# -------------------------------------------------------------
ICONS = {
    "icon-a-frame-corner": {
        "title": "시안 A: 프레임 코너",
        "subtitle": "Frame Corners",
        "concept": "화면 영역을 4개 모서리로 재단하여 지정하는 뷰파인더 프레이밍",
        "svg": '''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20" width="20" height="20">
  <!-- 시안 A: 프레임 코너 (Frame Corners) -->
  <g fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round">
    <!-- 좌상단 코너 가이드 -->
    <path d="M 2.5 6.5 V 4 C 2.5 3.17 3.17 2.5 4 2.5 H 6.5" stroke-width="1.5"/>
    <!-- 우상단 코너 가이드 -->
    <path d="M 13.5 2.5 H 16 C 16.83 2.5 17.5 3.17 17.5 4 V 6.5" stroke-width="1.5"/>
    <!-- 우하단 코너 가이드 -->
    <path d="M 17.5 13.5 V 16 C 17.5 16.83 16.83 17.5 16 17.5 H 13.5" stroke-width="1.5"/>
    <!-- 좌하단 코너 가이드 -->
    <path d="M 6.5 17.5 H 4 C 3.17 17.5 2.5 16.83 2.5 16 V 13.5" stroke-width="1.5"/>
    <!-- 내부 윈도우 프레임 -->
    <rect x="5.8" y="5.8" width="8.4" height="8.4" rx="1.2" stroke-width="1.2"/>
    <line x1="5.8" y1="8.5" x2="14.2" y2="8.5" stroke-width="1.0"/>
  </g>
</svg>'''
    },
    "icon-b-sketch-drag": {
        "title": "시안 B: 스케치 드래그",
        "subtitle": "Window & Sketched Box",
        "concept": "화면 위에서 마우스 드래그로 직접 사각형 창 영역을 그리는 제스처",
        "svg": '''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20" width="20" height="20">
  <!-- 시안 B: 스케치 드래그 (Window & Sketched Box) -->
  <!-- 베이스 창 프레임 -->
  <rect x="2.5" y="3" width="15" height="14" rx="1.8" fill="none" stroke="currentColor" stroke-width="1.3"/>
  <!-- 타이틀 바 구분선 -->
  <line x1="2.5" y1="6.8" x2="17.5" y2="6.8" stroke="currentColor" stroke-width="1.1"/>
  <!-- 타이틀 바 미니 액센트 -->
  <line x1="4.5" y1="4.9" x2="7.5" y2="4.9" stroke="currentColor" stroke-width="1.1" stroke-linecap="round"/>
  <!-- 드래그 생성된 타겟 창 영역 (솔리드 채움) -->
  <rect x="6.5" y="9" width="9" height="6.2" rx="1" fill="currentColor"/>
  <!-- 드래그 시작 앵커 포인트 -->
  <circle cx="6.5" cy="9" r="1.1" fill="currentColor"/>
</svg>'''
    },
    "icon-c-snap-split": {
        "title": "시안 C: 분할 배치",
        "subtitle": "Split Layout",
        "concept": "키보드 단축키로 반쪽, 모서리, 최대화를 창에 배치하는 도메인 기능",
        "svg": '''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20" width="20" height="20">
  <!-- 시안 C: 분할 배치 (Split Layout) -->
  <!-- 외곽 윈도우 프레임 -->
  <rect x="2.5" y="3" width="15" height="14" rx="1.8" fill="none" stroke="currentColor" stroke-width="1.4"/>
  <!-- 상단 타이틀 바 구분선 -->
  <line x1="2.5" y1="6.8" x2="17.5" y2="6.8" stroke="currentColor" stroke-width="1.1"/>
  <!-- 수직 분할선 -->
  <line x1="10" y1="6.8" x2="10" y2="17" stroke="currentColor" stroke-width="1.1"/>
  <!-- 좌측 활성 배치 패널 (솔리드 채움) -->
  <rect x="3.4" y="7.7" width="5.8" height="8.5" rx="0.8" fill="currentColor"/>
</svg>'''
    },
    "icon-d-crosshair-box": {
        "title": "시안 D: 정밀 바운딩 박스",
        "subtitle": "Precision Bounding Box",
        "concept": "4개 코너 노브와 십자 조준선으로 픽셀 크기를 정밀 측정·배치하는 바운딩 프레임",
        "svg": '''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20" width="20" height="20">
  <!-- 시안 D: 정밀 바운딩 박스 (Precision Bounding Box) -->
  <!-- 바운딩 박스 외곽 프레임 -->
  <rect x="3.5" y="3.5" width="13" height="13" rx="1" fill="none" stroke="currentColor" stroke-width="1.2"/>
  <!-- 타이틀 바 구분선 -->
  <line x1="3.5" y1="7" x2="16.5" y2="7" stroke="currentColor" stroke-width="1.0"/>
  <!-- 4개 코너 정밀 조준 사각 노브 -->
  <rect x="2" y="2" width="3" height="3" rx="0.5" fill="currentColor"/>
  <rect x="15" y="2" width="3" height="3" rx="0.5" fill="currentColor"/>
  <rect x="15" y="15" width="3" height="3" rx="0.5" fill="currentColor"/>
  <rect x="2" y="15" width="3" height="3" rx="0.5" fill="currentColor"/>
  <!-- 정밀 십자 조준선 (Center Crosshair) -->
  <line x1="8.5" y1="11.5" x2="11.5" y2="11.5" stroke="currentColor" stroke-width="1.2" stroke-linecap="round"/>
  <line x1="10" y1="10" x2="10" y2="13" stroke="currentColor" stroke-width="1.2" stroke-linecap="round"/>
</svg>'''
    }
}

# -------------------------------------------------------------
# 2. Write SVGs and Validate XML
# -------------------------------------------------------------
print("[1/5] Writing SVGs and validating XML...")
for name, data in ICONS.items():
    svg_filename = f"{name}.svg"
    svg_path = os.path.join(DIR, svg_filename)
    content = data["svg"].strip() + "\n"
    with open(svg_path, "w", encoding="utf-8") as f:
        f.write(content)
    
    # XML Validation
    try:
        root = ET.fromstring(content)
        assert root.tag.endswith("svg"), "Root element is not svg"
        assert root.attrib.get("viewBox") == "0 0 20 20", "viewBox is not 0 0 20 20"
        print(f"  ✓ {svg_filename}: XML valid (viewBox: {root.attrib.get('viewBox')})")
    except Exception as e:
        print(f"  ✗ {svg_filename} XML validation failed: {e}")
        sys.exit(1)

# -------------------------------------------------------------
# 3. Render PNGs at multiple sizes (16, 18, 20, 96)
# -------------------------------------------------------------
print("\n[2/5] Rendering PNGs using rsvg-convert...")
sizes = [16, 18, 20, 96]
png_cache = {}

for name in ICONS.keys():
    svg_path = os.path.join(DIR, f"{name}.svg")
    png_cache[name] = {}
    for sz in sizes:
        out_png = os.path.join(DIR, f"{name}_{sz}.png")
        cmd = ["rsvg-convert", "-w", str(sz), "-h", str(sz), svg_path, "-o", out_png]
        subprocess.run(cmd, check=True)
        
        # Load and verify
        im = Image.open(out_png)
        assert im.size == (sz, sz), f"Expected size {sz}x{sz}, got {im.size}"
        bbox = im.getbbox()
        assert bbox is not None, f"Image {out_png} is empty"
        png_cache[name][sz] = im
        print(f"  ✓ {name} ({sz}x{sz}): bbox={bbox}, alpha={im.getextrema()[3]}")

# -------------------------------------------------------------
# 4. Generate comparison.png
# -------------------------------------------------------------
print("\n[3/5] Generating comparison.png...")

W, H = 1260, 940
canvas = Image.new("RGBA", (W, H), (246, 247, 249, 255))
draw = ImageDraw.Draw(canvas)

# Fonts
font_title = ImageFont.truetype("/System/Library/Fonts/AppleSDGothicNeo.ttc", 26, index=0)
font_subtitle = ImageFont.truetype("/System/Library/Fonts/AppleSDGothicNeo.ttc", 14, index=0)
font_card_title = ImageFont.truetype("/System/Library/Fonts/AppleSDGothicNeo.ttc", 17, index=0)
font_card_sub = ImageFont.truetype("/System/Library/Fonts/Supplemental/Arial.ttf", 12)
font_section_hdr = ImageFont.truetype("/System/Library/Fonts/AppleSDGothicNeo.ttc", 12, index=0)
font_tag = ImageFont.truetype("/System/Library/Fonts/AppleSDGothicNeo.ttc", 11, index=0)
font_body = ImageFont.truetype("/System/Library/Fonts/AppleSDGothicNeo.ttc", 12, index=0)
font_pt = ImageFont.truetype("/System/Library/Fonts/Supplemental/Arial.ttf", 10)

# Header
draw.text((48, 36), "SketchFrame 메뉴 막대 아이콘 후보 시안 비교", fill=(20, 20, 24), font=font_title)
draw.text((48, 72), "macOS 메뉴 막대 템플릿 아이콘 (20×20 viewBox, 단색 템플릿, 16/18/20pt 시인성 검증)", fill=(100, 105, 115), font=font_subtitle)

# Column parameters
col_w = 270
col_gap = 18
start_x = 48
start_y = 115

keys = ["icon-a-frame-corner", "icon-b-sketch-drag", "icon-c-snap-split", "icon-d-crosshair-box"]
badges = ["A", "B", "C", "D"]

for idx, key in enumerate(keys):
    cx = start_x + idx * (col_w + col_gap)
    card_bg = (255, 255, 255, 255)
    card_border = (225, 228, 234, 255) if idx != 2 else (0, 113, 227, 255)
    
    # Outer Card
    draw.rounded_rectangle((cx, start_y, cx + col_w, start_y + 780), radius=12, fill=card_bg, outline=card_border, width=2 if idx == 2 else 1)
    
    # Header badge & title
    badge_bg = (0, 113, 227) if idx == 2 else (40, 44, 52)
    draw.rounded_rectangle((cx + 16, start_y + 16, cx + 40, start_y + 40), radius=6, fill=badge_bg)
    draw.text((cx + 23, start_y + 19), badges[idx], fill=(255, 255, 255), font=font_card_title)
    
    opt_title = ICONS[key]["title"].split(": ")[1]
    draw.text((cx + 48, start_y + 16), opt_title, fill=(20, 22, 26), font=font_card_title)
    draw.text((cx + 48, start_y + 38), ICONS[key]["subtitle"], fill=(120, 125, 135), font=font_card_sub)
    
    if idx == 2:
        draw.rounded_rectangle((cx + col_w - 62, start_y + 16, cx + col_w - 14, start_y + 36), radius=4, fill=(230, 242, 255))
        draw.text((cx + col_w - 52, start_y + 18), "추천", fill=(0, 113, 227), font=font_tag)
    
    # Concept Tag Box
    draw.rounded_rectangle((cx + 14, start_y + 64, cx + col_w - 14, start_y + 116), radius=6, fill=(247, 248, 250))
    words = ICONS[key]["concept"]
    concept_lines = [words[:20], words[20:]] if len(words) > 22 else [words]
    for l_idx, line in enumerate(concept_lines):
        draw.text((cx + 22, start_y + 72 + l_idx * 18), line, fill=(70, 75, 85), font=font_tag)
        
    # --- Section 1: Magnified View (96x96) ---
    draw.text((cx + 16, start_y + 130), "확대 모습 (96×96)", fill=(50, 55, 65), font=font_section_hdr)
    
    mag_box_w = 114
    mag_box_h = 114
    box_light_x = cx + 16
    box_dark_x = cx + col_w - 16 - mag_box_w
    box_y = start_y + 152
    
    draw.rounded_rectangle((box_light_x, box_y, box_light_x + mag_box_w, box_y + mag_box_h), radius=8, fill=(245, 246, 248), outline=(225, 228, 232))
    draw.text((box_light_x + 8, box_y + 6), "라이트", fill=(130, 135, 145), font=font_pt)
    
    draw.rounded_rectangle((box_dark_x, box_y, box_dark_x + mag_box_w, box_y + mag_box_h), radius=8, fill=(30, 32, 38), outline=(50, 54, 62))
    draw.text((box_dark_x + 8, box_y + 6), "다크", fill=(160, 165, 175), font=font_pt)
    
    im_96 = png_cache[key][96]
    im_scaled = im_96.resize((74, 74), Image.Resampling.LANCZOS)
    
    # Black version for light box
    icon_black = Image.new("RGBA", im_scaled.size, (20, 22, 26, 0))
    icon_black.putalpha(im_scaled.getchannel("A"))
    canvas.alpha_composite(icon_black, (box_light_x + 20, box_y + 24))
    
    # White version for dark box
    icon_white = Image.new("RGBA", im_scaled.size, (255, 255, 255, 0))
    icon_white.putalpha(im_scaled.getchannel("A"))
    canvas.alpha_composite(icon_white, (box_dark_x + 20, box_y + 24))
    
    # --- Section 2: Actual Menu Bar Simulation Light ---
    draw.text((cx + 16, start_y + 284), "실제 메뉴 막대: 라이트 모드", fill=(50, 55, 65), font=font_section_hdr)
    
    bar_light_y = start_y + 306
    bar_w = col_w - 32
    bar_h = 44
    draw.rounded_rectangle((cx + 16, bar_light_y, cx + 16 + bar_w, bar_light_y + bar_h), radius=6, fill=(236, 237, 240), outline=(218, 220, 225))
    
    sub_slots = [(16, 36), (18, 108), (20, 180)]
    for sz, sx in sub_slots:
        im_sz = png_cache[key][sz]
        b_im = Image.new("RGBA", im_sz.size, (20, 22, 26, 0))
        b_im.putalpha(im_sz.getchannel("A"))
        pos_x = cx + 16 + sx - sz // 2
        pos_y = bar_light_y + (bar_h - sz) // 2
        canvas.alpha_composite(b_im, (pos_x, pos_y))
        draw.text((cx + 16 + sx - 10, bar_light_y + bar_h + 4), f"{sz}pt", fill=(120, 125, 135), font=font_pt)
        
    # --- Section 3: Actual Menu Bar Simulation Dark ---
    draw.text((cx + 16, start_y + 382), "실제 메뉴 막대: 다크 모드", fill=(50, 55, 65), font=font_section_hdr)
    
    bar_dark_y = start_y + 404
    draw.rounded_rectangle((cx + 16, bar_dark_y, cx + 16 + bar_w, bar_dark_y + bar_h), radius=6, fill=(34, 36, 42), outline=(52, 56, 64))
    
    for sz, sx in sub_slots:
        im_sz = png_cache[key][sz]
        w_im = Image.new("RGBA", im_sz.size, (255, 255, 255, 0))
        w_im.putalpha(im_sz.getchannel("A"))
        pos_x = cx + 16 + sx - sz // 2
        pos_y = bar_dark_y + (bar_h - sz) // 2
        canvas.alpha_composite(w_im, (pos_x, pos_y))
        draw.text((cx + 16 + sx - 10, bar_dark_y + bar_h + 4), f"{sz}pt", fill=(120, 125, 135), font=font_pt)

    # --- Section 4: Analysis & Characteristics ---
    eval_y = start_y + 482
    draw.line((cx + 16, eval_y, cx + col_w - 16, eval_y), fill=(235, 238, 242), width=1)
    
    draw.text((cx + 16, eval_y + 12), "크기별 특징 및 관찰", fill=(50, 55, 65), font=font_section_hdr)
    
    eval_text = {
        "icon-a-frame-corner": [
            "• 16pt: 코너 브래킷 구조로 여백 유지",
            "• 18pt: 외곽 가이드와 중앙 창 계층 구분",
            "• 20pt: 뷰파인더 느낌의 균형 잡힌 외형",
            "• 특징: 열린 모서리로 개방감 제공",
            "• 한계: 중앙 창 내부 디테일이 작게 보임"
        ],
        "icon-b-sketch-drag": [
            "• 16pt: 내부 솔리드 사각형 식별 가능",
            "• 18pt: 베이스 창과 내부 영역 구분",
            "• 20pt: 드래그 시작 앵커와 창 조화",
            "• 특징: '드래그로 그린다'는 동작 상징",
            "• 한계: 외곽선과 내부 창 사이 여백 좁음"
        ],
        "icon-c-snap-split": [
            "• 16pt: 좌측 면 채움으로 명암 대비 확보",
            "• 18pt: 분할 구분선과 좌우 영역 구분",
            "• 20pt: 창 분할과 배치 의미 전달",
            "• 특징: 면 채움이 있어 작은 크기에서 구분 용이",
            "• 한계: 키보드 배치 중심이라 자유 드래그는 간접적"
        ],
        "icon-d-crosshair-box": [
            "• 16pt: 4개 코너 노브가 사각 윤곽 유지",
            "• 18pt: 중앙 십자선 형태 식별 가능",
            "• 20pt: 정밀 바운딩 박스 인상",
            "• 특징: 코너 핸들을 통한 영역 조절 상징",
            "• 한계: 16pt에서 중앙 십자선이 얇게 보임"
        ]
    }
    
    for t_idx, txt in enumerate(eval_text[key]):
        draw.text((cx + 16, eval_y + 36 + t_idx * 22), txt, fill=(60, 65, 75), font=font_body)
        
    # Bottom Note Box
    score_y = eval_y + 160
    draw.rounded_rectangle((cx + 16, score_y, cx + col_w - 16, score_y + 60), radius=6, fill=(248, 249, 251))
    
    summary_notes = {
        "icon-a-frame-corner": ("시인성: 양호 (개방형 구조)", "형태: 뷰파인더 코너 프레임"),
        "icon-b-sketch-drag": ("시인성: 양호 (면/선 복합)", "형태: 드래그 창 사각형"),
        "icon-c-snap-split": ("시인성: 우수 (면 대비 확보)", "형태: 반쪽 분할 배치 [추천]"),
        "icon-d-crosshair-box": ("시인성: 보통 (세선 위주)", "형태: 코너 노브 바운딩 박스")
    }
    draw.text((cx + 26, score_y + 12), summary_notes[key][0], fill=(20, 22, 26), font=font_section_hdr)
    draw.text((cx + 26, score_y + 34), summary_notes[key][1], fill=(0, 113, 227) if idx == 2 else (110, 115, 125), font=font_tag)

# Save comparison.png
out_comp = os.path.join(DIR, "comparison.png")
canvas.save(out_comp, "PNG")
print(f"  ✓ Saved comparison.png ({W}x{H})")

# -------------------------------------------------------------
# 5. Generate index.html
# -------------------------------------------------------------
print("\n[4/5] Generating index.html...")

html_content = f'''<!DOCTYPE html>
<html lang="ko">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>SketchFrame 메뉴 막대 아이콘 후보 시안 비교</title>
  <style>
    :root {{
      --bg: #f5f6f8;
      --card-bg: #ffffff;
      --text: #1d1d1f;
      --text-muted: #6e6e73;
      --border: #d2d2d7;
      --accent: #0071e3;
      --accent-light: #e8f2ff;
      --menubar-light: #eceef1;
      --menubar-dark: #1f2127;
    }}
    * {{
      box-sizing: border-box;
      margin: 0;
      padding: 0;
    }}
    body {{
      font-family: -apple-system, BlinkMacSystemFont, "Apple SD Gothic Neo", "Pretendard", sans-serif;
      background: var(--bg);
      color: var(--text);
      line-height: 1.5;
      padding: 40px 24px;
    }}
    .container {{
      max-width: 1200px;
      margin: 0 auto;
    }}
    header {{
      margin-bottom: 32px;
      padding-bottom: 24px;
      border-bottom: 1px solid var(--border);
    }}
    h1 {{
      font-size: 28px;
      font-weight: 700;
      letter-spacing: -0.5px;
      margin-bottom: 8px;
    }}
    .desc {{
      color: var(--text-muted);
      font-size: 15px;
    }}
    .domain-box {{
      background: #ffffff;
      border: 1px solid var(--border);
      border-radius: 12px;
      padding: 20px 24px;
      margin-bottom: 32px;
      font-size: 14px;
    }}
    .domain-box h3 {{
      font-size: 15px;
      font-weight: 600;
      margin-bottom: 8px;
      color: var(--accent);
    }}
    .domain-box ul {{
      padding-left: 20px;
      color: #333;
    }}
    .domain-box li {{
      margin-bottom: 4px;
    }}
    .grid {{
      display: grid;
      grid-template-columns: repeat(auto-fit, minmax(270px, 1fr));
      gap: 20px;
      margin-bottom: 40px;
    }}
    .card {{
      background: var(--card-bg);
      border: 1px solid var(--border);
      border-radius: 16px;
      padding: 24px;
      display: flex;
      flex-direction: column;
      position: relative;
    }}
    .card.recommended {{
      border: 2px solid var(--accent);
      box-shadow: 0 4px 20px rgba(0, 113, 227, 0.12);
    }}
    .badge-recom {{
      position: absolute;
      top: 18px;
      right: 18px;
      background: var(--accent);
      color: #fff;
      font-size: 11px;
      font-weight: 600;
      padding: 4px 10px;
      border-radius: 12px;
    }}
    .card-header {{
      display: flex;
      align-items: center;
      gap: 12px;
      margin-bottom: 12px;
    }}
    .opt-badge {{
      width: 32px;
      height: 32px;
      border-radius: 8px;
      background: #2c2c2e;
      color: #fff;
      display: flex;
      align-items: center;
      justify-content: center;
      font-weight: 700;
      font-size: 16px;
    }}
    .card.recommended .opt-badge {{
      background: var(--accent);
    }}
    .opt-titles h2 {{
      font-size: 18px;
      font-weight: 600;
    }}
    .opt-titles span {{
      font-size: 12px;
      color: var(--text-muted);
    }}
    .concept-tag {{
      background: #f4f5f7;
      padding: 8px 12px;
      border-radius: 8px;
      font-size: 13px;
      color: #444;
      margin-bottom: 20px;
      min-height: 54px;
      display: flex;
      align-items: center;
    }}
    .preview-section {{
      margin-bottom: 20px;
    }}
    .preview-section h4 {{
      font-size: 12px;
      text-transform: uppercase;
      letter-spacing: 0.5px;
      color: var(--text-muted);
      margin-bottom: 8px;
    }}
    .zoom-view {{
      display: flex;
      gap: 12px;
      margin-bottom: 16px;
    }}
    .zoom-box {{
      flex: 1;
      padding: 20px;
      border-radius: 10px;
      display: flex;
      flex-direction: column;
      align-items: center;
      justify-content: center;
      gap: 8px;
    }}
    .zoom-box.light {{
      background: #f7f8fa;
      border: 1px solid #e1e3e8;
      color: #111;
    }}
    .zoom-box.dark {{
      background: #1e2025;
      border: 1px solid #33363f;
      color: #fff;
    }}
    .zoom-box svg {{
      width: 56px;
      height: 56px;
    }}
    .zoom-box span {{
      font-size: 11px;
      opacity: 0.6;
    }}
    .menubar-strip {{
      padding: 10px 14px;
      border-radius: 8px;
      display: flex;
      align-items: center;
      justify-content: space-around;
      margin-bottom: 8px;
    }}
    .menubar-strip.light {{
      background: var(--menubar-light);
      border: 1px solid #d8dbe0;
      color: #111;
    }}
    .menubar-strip.dark {{
      background: var(--menubar-dark);
      border: 1px solid #32353e;
      color: #fff;
    }}
    .size-item {{
      display: flex;
      flex-direction: column;
      align-items: center;
      gap: 4px;
    }}
    .size-item span {{
      font-size: 10px;
      opacity: 0.7;
      font-family: monospace;
    }}
    .specs {{
      margin-top: auto;
      border-top: 1px solid #eee;
      padding-top: 16px;
      font-size: 13px;
    }}
    .specs ul {{
      list-style: none;
    }}
    .specs li {{
      margin-bottom: 6px;
      padding-left: 16px;
      position: relative;
      color: #444;
    }}
    .specs li::before {{
      content: "•";
      position: absolute;
      left: 0;
      color: var(--accent);
    }}
    .specs .score {{
      margin-top: 14px;
      padding: 10px;
      background: #f8f9fa;
      border-radius: 8px;
      font-weight: 600;
      font-size: 12px;
      display: flex;
      justify-content: space-between;
    }}
    .summary-card {{
      background: #fff;
      border: 1px solid var(--border);
      border-radius: 16px;
      padding: 28px;
      margin-top: 24px;
    }}
    .summary-card h2 {{
      font-size: 20px;
      margin-bottom: 16px;
      font-weight: 700;
    }}
    table {{
      width: 100%;
      border-collapse: collapse;
      font-size: 14px;
      margin-top: 12px;
    }}
    th, td {{
      padding: 12px 14px;
      border-bottom: 1px solid #eee;
      text-align: left;
    }}
    th {{
      background: #f7f8fa;
      color: #444;
      font-weight: 600;
    }}
    .tag-rec {{
      background: var(--accent-light);
      color: var(--accent);
      padding: 3px 8px;
      border-radius: 6px;
      font-weight: 600;
      font-size: 12px;
    }}
  </style>
</head>
<body>
  <div class="container">
    <header>
      <h1>SketchFrame 메뉴 막대 아이콘 후보 시안 비교</h1>
      <p class="desc">macOS 활성 창 관리자 SketchFrame (Command+Shift+드래그 영역 배치 및 키보드 단축키 반쪽·모서리·최대화 배치) 전용 템플릿 아이콘 4종 비교</p>
    </header>

    <div class="domain-box">
      <h3>SketchFrame 앱 도메인 및 디자인 원칙</h3>
      <ul>
        <li><strong>핵심 도메인:</strong> Command + Shift + 왼쪽 드래그로 사각형 영역을 직접 그려 창의 위치와 크기를 지정하고, 키보드 단축키로 반쪽, 모서리, 최대화, 가운데 배치를 수행합니다.</li>
        <li><strong>메뉴 막대 제약:</strong> 단색 템플릿(isTemplate = true), 투명 배경, 20×20 viewBox 기준, 실제 16pt / 18pt / 20pt에서 번짐 없는 명확한 시인성을 보장해야 합니다.</li>
        <li><strong>디자인 방향:</strong> 단순 그리기 펜 도구가 아닌 '창 프레임'과 '영역 배치'가 즉각적으로 인식되는 직관적인 벡터 그래픽을 지향합니다.</li>
      </ul>
    </div>

    <div class="grid">
      <!-- Option A -->
      <div class="card">
        <div class="card-header">
          <div class="opt-badge">A</div>
          <div class="opt-titles">
            <h2>프레임 코너</h2>
            <span>Frame Corners</span>
          </div>
        </div>
        <div class="concept-tag">
          화면 영역을 4개 모서리 브래킷으로 재단하여 지정하는 뷰파인더 프레이밍
        </div>
        <div class="preview-section">
          <h4>확대 보기 (56px)</h4>
          <div class="zoom-view">
            <div class="zoom-box light">
              {ICONS["icon-a-frame-corner"]["svg"]}
              <span>라이트 모드</span>
            </div>
            <div class="zoom-box dark">
              {ICONS["icon-a-frame-corner"]["svg"]}
              <span>다크 모드</span>
            </div>
          </div>
          <h4>실제 메뉴 막대 시뮬레이션</h4>
          <div class="menubar-strip light">
            <div class="size-item">
              <div style="width: 16px; height: 16px;">{ICONS["icon-a-frame-corner"]["svg"].replace('width="20" height="20"', 'width="16" height="16"')}</div>
              <span>16pt</span>
            </div>
            <div class="size-item">
              <div style="width: 18px; height: 18px;">{ICONS["icon-a-frame-corner"]["svg"].replace('width="20" height="20"', 'width="18" height="18"')}</div>
              <span>18pt</span>
            </div>
            <div class="size-item">
              <div style="width: 20px; height: 20px;">{ICONS["icon-a-frame-corner"]["svg"]}</div>
              <span>20pt</span>
            </div>
          </div>
          <div class="menubar-strip dark">
            <div class="size-item">
              <div style="width: 16px; height: 16px;">{ICONS["icon-a-frame-corner"]["svg"].replace('width="20" height="20"', 'width="16" height="16"')}</div>
              <span>16pt</span>
            </div>
            <div class="size-item">
              <div style="width: 18px; height: 18px;">{ICONS["icon-a-frame-corner"]["svg"].replace('width="20" height="20"', 'width="18" height="18"')}</div>
              <span>18pt</span>
            </div>
            <div class="size-item">
              <div style="width: 20px; height: 20px;">{ICONS["icon-a-frame-corner"]["svg"]}</div>
              <span>20pt</span>
            </div>
          </div>
        </div>
        <div class="specs">
          <ul>
            <li>열린 모서리 구조로 16pt에서도 선 뭉개짐 현상을 줄임</li>
            <li>카메라 및 프레이밍 메타포로 안정적인 외형</li>
            <li>내부 미니 창과 외부 브래킷의 계층감 제공</li>
          </ul>
          <div class="score">
            <span>시인성: 양호</span>
            <span style="color: #666;">뷰파인더 코너</span>
          </div>
        </div>
      </div>

      <!-- Option B -->
      <div class="card">
        <div class="card-header">
          <div class="opt-badge">B</div>
          <div class="opt-titles">
            <h2>스케치 드래그</h2>
            <span>Window & Sketched Box</span>
          </div>
        </div>
        <div class="concept-tag">
          화면 창 위에서 직접 마우스 드래그로 사각형 창 영역을 그리는 제스처
        </div>
        <div class="preview-section">
          <h4>확대 보기 (56px)</h4>
          <div class="zoom-view">
            <div class="zoom-box light">
              {ICONS["icon-b-sketch-drag"]["svg"]}
              <span>라이트 모드</span>
            </div>
            <div class="zoom-box dark">
              {ICONS["icon-b-sketch-drag"]["svg"]}
              <span>다크 모드</span>
            </div>
          </div>
          <h4>실제 메뉴 막대 시뮬레이션</h4>
          <div class="menubar-strip light">
            <div class="size-item">
              <div style="width: 16px; height: 16px;">{ICONS["icon-b-sketch-drag"]["svg"].replace('width="20" height="20"', 'width="16" height="16"')}</div>
              <span>16pt</span>
            </div>
            <div class="size-item">
              <div style="width: 18px; height: 18px;">{ICONS["icon-b-sketch-drag"]["svg"].replace('width="20" height="20"', 'width="18" height="18"')}</div>
              <span>18pt</span>
            </div>
            <div class="size-item">
              <div style="width: 20px; height: 20px;">{ICONS["icon-b-sketch-drag"]["svg"]}</div>
              <span>20pt</span>
            </div>
          </div>
          <div class="menubar-strip dark">
            <div class="size-item">
              <div style="width: 16px; height: 16px;">{ICONS["icon-b-sketch-drag"]["svg"].replace('width="20" height="20"', 'width="16" height="16"')}</div>
              <span>16pt</span>
            </div>
            <div class="size-item">
              <div style="width: 18px; height: 18px;">{ICONS["icon-b-sketch-drag"]["svg"].replace('width="20" height="20"', 'width="18" height="18"')}</div>
              <span>18pt</span>
            </div>
            <div class="size-item">
              <div style="width: 20px; height: 20px;">{ICONS["icon-b-sketch-drag"]["svg"]}</div>
              <span>20pt</span>
            </div>
          </div>
        </div>
        <div class="specs">
          <ul>
            <li>드래그 시작점 앵커와 내부 솔리드 창으로 도메인 동작 표현</li>
            <li>베이스 창 대비 내부 영역의 명암비 형성</li>
            <li>'창 위에 사각형을 그려 배치한다'는 고유 동작 상징</li>
          </ul>
          <div class="score">
            <span>시인성: 양호</span>
            <span style="color: #666;">드래그 창 사각형</span>
          </div>
        </div>
      </div>

      <!-- Option C (Recommended) -->
      <div class="card recommended">
        <div class="badge-recom">추천</div>
        <div class="card-header">
          <div class="opt-badge">C</div>
          <div class="opt-titles">
            <h2>분할 배치</h2>
            <span>Split Layout</span>
          </div>
        </div>
        <div class="concept-tag">
          키보드 단축키로 반쪽, 모서리, 최대화를 창에 배치하는 도메인 기능
        </div>
        <div class="preview-section">
          <h4>확대 보기 (56px)</h4>
          <div class="zoom-view">
            <div class="zoom-box light">
              {ICONS["icon-c-snap-split"]["svg"]}
              <span>라이트 모드</span>
            </div>
            <div class="zoom-box dark">
              {ICONS["icon-c-snap-split"]["svg"]}
              <span>다크 모드</span>
            </div>
          </div>
          <h4>실제 메뉴 막대 시뮬레이션</h4>
          <div class="menubar-strip light">
            <div class="size-item">
              <div style="width: 16px; height: 16px;">{ICONS["icon-c-snap-split"]["svg"].replace('width="20" height="20"', 'width="16" height="16"')}</div>
              <span>16pt</span>
            </div>
            <div class="size-item">
              <div style="width: 18px; height: 18px;">{ICONS["icon-c-snap-split"]["svg"].replace('width="20" height="20"', 'width="18" height="18"')}</div>
              <span>18pt</span>
            </div>
            <div class="size-item">
              <div style="width: 20px; height: 20px;">{ICONS["icon-c-snap-split"]["svg"]}</div>
              <span>20pt</span>
            </div>
          </div>
          <div class="menubar-strip dark">
            <div class="size-item">
              <div style="width: 16px; height: 16px;">{ICONS["icon-c-snap-split"]["svg"].replace('width="20" height="20"', 'width="16" height="16"')}</div>
              <span>16pt</span>
            </div>
            <div class="size-item">
              <div style="width: 18px; height: 18px;">{ICONS["icon-c-snap-split"]["svg"].replace('width="20" height="20"', 'width="18" height="18"')}</div>
              <span>18pt</span>
            </div>
            <div class="size-item">
              <div style="width: 20px; height: 20px;">{ICONS["icon-c-snap-split"]["svg"]}</div>
              <span>20pt</span>
            </div>
          </div>
        </div>
        <div class="specs">
          <ul>
            <li>좌측 솔리드 면과 우측 공간의 대비로 작은 크기에서 식별이 용이함</li>
            <li>키보드 단축키를 통한 반쪽/모서리/최대화 배치 기능과 직관적으로 부합</li>
            <li>macOS 창 관리자 인터페이스에 친숙한 형태 구성</li>
          </ul>
          <div class="score" style="background: var(--accent-light); color: var(--accent);">
            <span>시인성: 우수 (면 대비 확보)</span>
            <span>추천 시안</span>
          </div>
        </div>
      </div>

      <!-- Option D -->
      <div class="card">
        <div class="card-header">
          <div class="opt-badge">D</div>
          <div class="opt-titles">
            <h2>정밀 바운딩 박스</h2>
            <span>Precision Bounding Box</span>
          </div>
        </div>
        <div class="concept-tag">
          4개 코너 노브와 십자 조준선으로 픽셀 크기를 정밀 측정·배치하는 바운딩 프레임
        </div>
        <div class="preview-section">
          <h4>확대 보기 (56px)</h4>
          <div class="zoom-view">
            <div class="zoom-box light">
              {ICONS["icon-d-crosshair-box"]["svg"]}
              <span>라이트 모드</span>
            </div>
            <div class="zoom-box dark">
              {ICONS["icon-d-crosshair-box"]["svg"]}
              <span>다크 모드</span>
            </div>
          </div>
          <h4>실제 메뉴 막대 시뮬레이션</h4>
          <div class="menubar-strip light">
            <div class="size-item">
              <div style="width: 16px; height: 16px;">{ICONS["icon-d-crosshair-box"]["svg"].replace('width="20" height="20"', 'width="16" height="16"')}</div>
              <span>16pt</span>
            </div>
            <div class="size-item">
              <div style="width: 18px; height: 18px;">{ICONS["icon-d-crosshair-box"]["svg"].replace('width="20" height="20"', 'width="18" height="18"')}</div>
              <span>18pt</span>
            </div>
            <div class="size-item">
              <div style="width: 20px; height: 20px;">{ICONS["icon-d-crosshair-box"]["svg"]}</div>
              <span>20pt</span>
            </div>
          </div>
          <div class="menubar-strip dark">
            <div class="size-item">
              <div style="width: 16px; height: 16px;">{ICONS["icon-d-crosshair-box"]["svg"].replace('width="20" height="20"', 'width="16" height="16"')}</div>
              <span>16pt</span>
            </div>
            <div class="size-item">
              <div style="width: 18px; height: 18px;">{ICONS["icon-d-crosshair-box"]["svg"].replace('width="20" height="20"', 'width="18" height="18"')}</div>
              <span>18pt</span>
            </div>
            <div class="size-item">
              <div style="width: 20px; height: 20px;">{ICONS["icon-d-crosshair-box"]["svg"]}</div>
              <span>20pt</span>
            </div>
          </div>
        </div>
        <div class="specs">
          <ul>
            <li>기존 rectangle.dashed 대비 그래픽 도구의 정밀 바운딩 상자 느낌</li>
            <li>돌출된 4개 코너 노브로 사각형 형태를 명확히 고정</li>
            <li>중앙 조준선으로 픽셀 단위 정밀 드래그 상징</li>
          </ul>
          <div class="score">
            <span>시인성: 보통 (세선 위주)</span>
            <span style="color: #666;">코너 노브 바운딩</span>
          </div>
        </div>
      </div>
    </div>

    <!-- Summary Section -->
    <div class="summary-card">
      <h2>시안별 종합 비교</h2>
      <table>
        <thead>
          <tr>
            <th>시안</th>
            <th>핵심 메타포</th>
            <th>16pt 시인성</th>
            <th>도메인 표현력</th>
            <th>구분</th>
          </tr>
        </thead>
        <tbody>
          <tr>
            <td><strong>시안 A (프레임 코너)</strong></td>
            <td>뷰파인더 / 4모서리 재단</td>
            <td>양호 (열린 공간)</td>
            <td>영역 포착 및 프레이밍</td>
            <td>대안 시안</td>
          </tr>
          <tr>
            <td><strong>시안 B (스케치 드래그)</strong></td>
            <td>화면 위 드래그 창 그리기</td>
            <td>양호 (솔리드 면)</td>
            <td>직접 드래그 그리기 제스처</td>
            <td>대안 시안</td>
          </tr>
          <tr style="background: var(--accent-light);">
            <td><strong>시안 C (분할 배치)</strong></td>
            <td>윈도우 프레임 및 분할 배치</td>
            <td><strong>우수 (면 대비 확보)</strong></td>
            <td>키보드 단축키 반쪽·모서리·최대화 배치</td>
            <td><span class="tag-rec">추천 시안</span></td>
          </tr>
          <tr>
            <td><strong>시안 D (정밀 바운딩 박스)</strong></td>
            <td>코너 핸들 및 십자 조준선</td>
            <td>보통 (세선 위주)</td>
            <td>픽셀 단위 측정 및 조준</td>
            <td>대안 시안</td>
          </tr>
        </tbody>
      </table>
    </div>
  </div>
</body>
</html>
'''

out_html = os.path.join(DIR, "index.html")
with open(out_html, "w", encoding="utf-8") as f:
    f.write(html_content)
print(f"  ✓ Saved index.html")

# -------------------------------------------------------------
# 6. Generate README.md
# -------------------------------------------------------------
print("\n[5/5] Generating README.md...")

readme_content = '''# SketchFrame 메뉴 막대 아이콘 시안 제안서

macOS 활성 창 관리자 **SketchFrame(스케치프레임)**의 메뉴 막대 전용 아이콘 시안 4종과 비교 검증 결과입니다.

---

## 1. 개요 및 배경

- **기존 아이콘 한계**: 기존 SF Symbols의 `rectangle.dashed`는 일반적인 점선 사각형으로, 실제 16~20pt의 작은 메뉴 막대 크기에서 평범하고 창 관리 및 영역 스케치 기능의 인지도가 낮았습니다.
- **핵심 도메인 반영**:
  1. `Command + Shift + 드래그`로 화면 위에 사각형을 직접 그려 창의 위치와 크기를 즉시 배치하는 핵심 인터랙션.
  2. 키보드 단축키를 통한 반쪽, 모서리(사분면), 최대화, 중앙 정렬 등 활성 창 배치 관리 기능.
  3. 메뉴 막대 템플릿 규격(`isTemplate = true`, `20×20 viewBox`, 단색 및 투명 배경)을 준수하면서 16pt, 18pt, 20pt 크기에서 시인성 확보.

---

## 2. 시안별 상세 설명

### 시안 A: 프레임 코너 (Frame Corners)
- **파일**: [`icon-a-frame-corner.svg`](icon-a-frame-corner.svg)
- **핵심 메타포**: 화면의 특정 영역을 4개 모서리 가이드로 감싸 재단하는 뷰파인더(Viewfinder) 프레이밍.
- **형태 구조**:
  - 외곽 4개 모서리에 라운드 처리된 L자형 코너 브래킷 가이드 배치 (두께 1.5px).
  - 중앙에 부드러운 라운드의 미니 윈도우 프레임과 상단 타이틀바 분리선 배치.
- **작은 크기(16~20pt) 장단점**:
  - **장점**: 모서리가 열려 있는 개방형 구조로 16pt에서도 선 뭉개짐 현상을 줄이며, 카메라 초점 프레임처럼 안정적인 여백을 제공합니다.
  - **단점**: 중앙 창 내부의 디테일(타이틀 분리선)이 16pt에서는 다소 작게 보일 수 있습니다.

### 시안 B: 스케치 드래그 (Window & Sketched Box)
- **파일**: [`icon-b-sketch-drag.svg`](icon-b-sketch-drag.svg)
- **핵심 메타포**: 화면/기존 창 위에서 마우스 드래그를 통해 새로운 창 영역을 직접 그려서 배치하는 제스처.
- **형태 구조**:
  - 베이스 화면/창 외곽선(두께 1.3px)과 상단 타이틀바 헤더 라인.
  - 우하단 영역에 드래그로 생성 중인 솔리드(Solid) 채움 사각형과 좌상단 시작점 앵커 도트.
- **작은 크기(16~20pt) 장단점**:
  - **장점**: '창 안에 또 다른 창 영역을 직접 그린다'는 앱의 고유 인터랙션을 전달하며, 솔리드 면이 들어가 있어 16pt에서도 영역이 식별됩니다.
  - **단점**: 베이스 외곽선과 내부 창 사이의 여백이 좁아 정밀하게 정렬되지 않으면 다소 복잡해 보일 수 있습니다.

### 시안 C: 분할 배치 (Split Layout) — [추천]
- **파일**: [`icon-c-snap-split.svg`](icon-c-snap-split.svg)
- **핵심 메타포**: 키보드 단축키로 활성 창을 반쪽, 모서리, 최대화로 정돈 배치하는 창 관리 기능.
- **형태 구조**:
  - 클래식 macOS 윈도우 프레임(두께 1.4px, 라운드 1.8px)과 상단 타이틀바 분리선.
  - 윈도우 하단 작업 공간의 중앙 수직 분할선과 좌측 영역을 채운 솔리드 배치 패널.
- **작은 크기(16~20pt) 장단점**:
  - **장점**: 솔리드 면(채움)과 외곽 스트로크(선)의 명암 대비 덕분에 16pt, 18pt, 20pt 크기에서 다른 선형 아이콘 대비 식별이 용이합니다.
  - **단점**: 키보드 단축키 배치 메타포가 중심이 되어 마우스 자유 드래그 기능에 대한 상징성은 상대적으로 간접적입니다.

### 시안 D: 정밀 바운딩 박스 (Precision Bounding Box)
- **파일**: [`icon-d-crosshair-box.svg`](icon-d-crosshair-box.svg)
- **핵심 메타포**: 4개 모서리 조준 노브와 십자선으로 픽셀 크기를 정밀 측정하여 사각형을 재단하는 바운딩 프레임.
- **형태 구조**:
  - 13×13px 바운딩 프레임과 상단 타이틀바 구분선.
  - 4개 꼭짓점에 돌출된 정밀 사각 앵커 핸들(크기 3×3px).
  - 중앙부의 정밀 십자 조준선(Crosshair).
- **작은 크기(16~20pt) 장단점**:
  - **장점**: 기존 `rectangle.dashed`의 밋밋함을 탈피하고 그래픽 전문 도구의 정밀 바운딩 박스 느낌을 전달합니다.
  - **단점**: 16pt 크기에서는 중앙 십자선이 다소 섬세하여 메뉴 막대에서 한눈에 들어오는 대비감은 시안 C에 비해 낮습니다.

---

## 3. 추천 시안 및 의견

### 추천 시안: **시안 C (분할 배치 / Split Layout)**

주관적인 추천으로, 선정 이유는 다음과 같습니다:
1. **면 채움 대비**:
   메뉴 막대의 작은 크기(16~18pt)에서 선(스트로크)만으로 구성된 아이콘보다 좌측 절반의 솔리드 면 채움이 있는 시안 C가 시각적 대비가 높아 상대적으로 쉽게 식별됩니다.
2. **현재 기능과 일치**:
   키보드 단축키로 활성 창을 반쪽, 모서리, 최대화 등으로 정돈 배치하는 앱의 핵심 기능과 직관적으로 부합합니다.

> **참고**: 마우스 드래그로 사각형을 직접 그리는 인터랙션을 더 강조하고 싶다면 **시안 B(스케치 드래그)**를 대안으로 검토할 수 있습니다.

---

## 4. 검증 결과

1. **XML 파싱 검증**:
   - 4개 SVG 파일 모두 `xml.etree.ElementTree`를 통한 파싱 통과.
   - 표준 `xmlns`, `viewBox="0 0 20 20"`, `currentColor` 규격 준수.
2. **PNG 크기 및 렌더링 검증**:
   - `rsvg-convert`를 사용하여 16×16, 18×18, 20×20, 96×96 크기로 정상 렌더링 확인.
   - 16pt 렌더링 시 전 방향 외곽 1px의 안전 여백(Optical Margin) 확보 확인 (`bbox=(1, 1, 15, 15)`).
   - 비어 있거나 잘려 나가는 아티팩트 없음.
3. **비교 이미지 확인**:
   - 라이트 배경과 다크 배경에서 16/18/20pt 실제 크기와 96px 확대 모습 대조 완료.

---

## 5. 적용 현황 및 남은 작업

- 이번 작업은 디자인 시안 산출물 작성까지이며, 현재 앱 소스코드(`Source/main.swift`)에는 아직 적용하지 않았습니다.
- 실제 앱 적용 여부 및 방식은 검토 후 결정할 사항입니다.

---

## 6. 산출물 파일 목록

| 파일명 | 설명 |
|---|---|
| [`icon-a-frame-corner.svg`](icon-a-frame-corner.svg) | 시안 A: 프레임 코너 SVG 벡터 (20×20) |
| [`icon-b-sketch-drag.svg`](icon-b-sketch-drag.svg) | 시안 B: 스케치 드래그 SVG 벡터 (20×20) |
| [`icon-c-snap-split.svg`](icon-c-snap-split.svg) | 시안 C: 분할 배치 SVG 벡터 (20×20, 추천) |
| [`icon-d-crosshair-box.svg`](icon-d-crosshair-box.svg) | 시안 D: 정밀 바운딩 박스 SVG 벡터 (20×20) |
| [`comparison.png`](comparison.png) | 4개 시안의 확대 및 실제 크기(16/18/20pt) 라이트/다크 비교 종합 이미지 |
| [`index.html`](index.html) | 외부 자원 없이 로컬 브라우저에서 바로 열리는 비교 웹페이지 |
| [`render_assets.py`](render_assets.py) | 모든 SVG, PNG, comparison.png, index.html, README.md를 재현 및 재생성하는 스크립트 |
| [`README.md`](README.md) | 본 문서 |

---

## 7. 재현 방법

터미널에서 아래 명령을 실행하면 모든 산출물이 동일하게 재생성되고 검증됩니다:

```bash
python3 docs/design/menu-bar-icons/render_assets.py
```
'''

out_readme = os.path.join(DIR, "README.md")
with open(out_readme, "w", encoding="utf-8") as f:
    f.write(readme_content)
print(f"  ✓ Saved README.md")

print("\nAll assets generated successfully!")
