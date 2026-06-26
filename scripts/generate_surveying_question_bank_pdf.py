from __future__ import annotations

from collections import defaultdict
from dataclasses import dataclass
from html import escape
from math import acos, atan2, cos, degrees, hypot, pi, radians, sin, sqrt
from pathlib import Path
import re
from typing import Iterable, Sequence

import arabic_reshaper
from bidi.algorithm import get_display
from reportlab.lib import colors
from reportlab.lib.enums import TA_CENTER, TA_LEFT, TA_RIGHT
from reportlab.lib.pagesizes import A4
from reportlab.lib.styles import ParagraphStyle, getSampleStyleSheet
from reportlab.lib.units import cm, mm
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.platypus import (
    Flowable,
    PageBreak,
    Paragraph,
    SimpleDocTemplate,
    Spacer,
    Table,
    TableStyle,
)


ROOT = Path(__file__).resolve().parents[1]
OUTPUT_PDF = ROOT / "output" / "pdf" / "surveying_expected_questions_bank_ar.pdf"
ARABIC_RE = re.compile(r"[\u0600-\u06ff]")


@dataclass(frozen=True)
class Question:
    section: str
    title: str
    prompt: str
    solution: str
    diagram: str | None = None


def has_arabic(text: str) -> bool:
    return bool(ARABIC_RE.search(text))


def rtl(text: str) -> str:
    if not text:
        return ""
    return get_display(arabic_reshaper.reshape(text))


def display_text(text: str) -> str:
    lines = []
    for line in text.splitlines():
        lines.append(rtl(line) if has_arabic(line) else line)
    return "<br/>".join(escape(line) for line in lines)


def fmt(value: float, digits: int = 3) -> str:
    text = f"{value:.{digits}f}"
    if "." in text:
        text = text.rstrip("0").rstrip(".")
    return text


def seconds_to_radians(seconds: float) -> float:
    return radians(seconds / 3600.0)


def circular_sector_metrics(
    radius_m: float,
    theta_deg: float,
    sigma_radius_m: float,
    sigma_theta_seconds: float,
) -> dict[str, float]:
    theta_rad = radians(theta_deg)
    sigma_theta_rad = seconds_to_radians(sigma_theta_seconds)
    area = 0.5 * radius_m**2 * theta_rad
    perimeter = 2.0 * radius_m + radius_m * theta_rad
    sigma_area = sqrt(
        (radius_m * theta_rad * sigma_radius_m) ** 2
        + (0.5 * radius_m**2 * sigma_theta_rad) ** 2
    )
    sigma_perimeter = sqrt(
        ((2.0 + theta_rad) * sigma_radius_m) ** 2
        + (radius_m * sigma_theta_rad) ** 2
    )
    return {
        "theta_rad": theta_rad,
        "area_m2": area,
        "perimeter_m": perimeter,
        "sigma_area_m2": sigma_area,
        "sigma_perimeter_m": sigma_perimeter,
    }


def weighted_mean(values: Sequence[float], sigmas: Sequence[float]) -> dict[str, float]:
    if len(values) != len(sigmas):
        raise ValueError("values and sigmas must have the same length")
    weights = [1.0 / (sigma**2) for sigma in sigmas]
    total_weight = sum(weights)
    mean = sum(value * weight for value, weight in zip(values, weights)) / total_weight
    return {
        "mean": mean,
        "sigma_mean": sqrt(1.0 / total_weight),
        "total_weight": total_weight,
    }


def project_point_to_line(
    point: tuple[float, float],
    line_a: tuple[float, float],
    line_b: tuple[float, float],
) -> tuple[float, float, float]:
    px, py = point
    ax, ay = line_a
    bx, by = line_b
    dx = bx - ax
    dy = by - ay
    t = ((px - ax) * dx + (py - ay) * dy) / (dx * dx + dy * dy)
    hx = ax + t * dx
    hy = ay + t * dy
    return hx, hy, hypot(px - hx, py - hy)


def line_intersection(
    p1: tuple[float, float],
    p2: tuple[float, float],
    p3: tuple[float, float],
    p4: tuple[float, float],
) -> tuple[float, float]:
    x1, y1 = p1
    x2, y2 = p2
    x3, y3 = p3
    x4, y4 = p4
    denominator = (x1 - x2) * (y3 - y4) - (y1 - y2) * (x3 - x4)
    if abs(denominator) < 1e-12:
        raise ValueError("lines are parallel")
    px = (
        (x1 * y2 - y1 * x2) * (x3 - x4)
        - (x1 - x2) * (x3 * y4 - y3 * x4)
    ) / denominator
    py = (
        (x1 * y2 - y1 * x2) * (y3 - y4)
        - (y1 - y2) * (x3 * y4 - y3 * x4)
    ) / denominator
    return px, py


def line_circle_intersections(
    point: tuple[float, float],
    direction: tuple[float, float],
    center: tuple[float, float],
    radius: float,
) -> list[tuple[float, float]]:
    px, py = point
    dx, dy = direction
    cx, cy = center
    fx = px - cx
    fy = py - cy
    a = dx * dx + dy * dy
    b = 2.0 * (fx * dx + fy * dy)
    c = fx * fx + fy * fy - radius * radius
    discriminant = b * b - 4.0 * a * c
    if discriminant < -1e-12:
        return []
    discriminant = max(discriminant, 0.0)
    root = sqrt(discriminant)
    ts = [(-b - root) / (2.0 * a), (-b + root) / (2.0 * a)]
    return [(px + t * dx, py + t * dy) for t in ts]


def circle_circle_intersections(
    c1: tuple[float, float],
    r1: float,
    c2: tuple[float, float],
    r2: float,
) -> list[tuple[float, float]]:
    x0, y0 = c1
    x1, y1 = c2
    dx = x1 - x0
    dy = y1 - y0
    d = hypot(dx, dy)
    if d == 0 or d > r1 + r2 or d < abs(r1 - r2):
        return []
    a = (r1 * r1 - r2 * r2 + d * d) / (2.0 * d)
    h = sqrt(max(r1 * r1 - a * a, 0.0))
    xm = x0 + a * dx / d
    ym = y0 + a * dy / d
    rx = -dy * h / d
    ry = dx * h / d
    return [(xm + rx, ym + ry), (xm - rx, ym - ry)]


class Sketch(Flowable):
    def __init__(self, kind: str, width: float = 10.5 * cm, height: float = 3.2 * cm):
        super().__init__()
        self.kind = kind
        self.width = width
        self.height = height

    def draw(self) -> None:
        canvas = self.canv
        canvas.saveState()
        canvas.setStrokeColor(colors.HexColor("#4a6178"))
        canvas.setFillColor(colors.HexColor("#edf3f8"))
        canvas.roundRect(0, 0, self.width, self.height, 5, stroke=1, fill=1)
        canvas.setStrokeColor(colors.HexColor("#213547"))
        canvas.setFillColor(colors.HexColor("#213547"))
        if self.kind == "projection":
            canvas.line(30, 35, self.width - 30, self.height - 30)
            canvas.circle(72, self.height - 38, 3, fill=1)
            canvas.line(72, self.height - 38, 104, 54)
            canvas.setDash(3, 2)
            canvas.line(104, 54, 104, 35)
            canvas.setDash()
            canvas.drawString(62, self.height - 30, "P")
            canvas.drawString(108, 58, "H")
            canvas.drawString(25, 24, "A")
            canvas.drawString(self.width - 25, self.height - 25, "B")
        elif self.kind == "line_line":
            canvas.line(35, 30, self.width - 35, self.height - 25)
            canvas.line(60, self.height - 25, self.width - 55, 25)
            canvas.circle(self.width / 2, self.height / 2 + 5, 4, fill=1)
            canvas.drawString(self.width / 2 + 8, self.height / 2 + 7, "I")
        elif self.kind == "line_circle":
            canvas.circle(self.width / 2, self.height / 2, 48, stroke=1, fill=0)
            canvas.line(40, 36, self.width - 40, self.height - 36)
            canvas.circle(self.width / 2 - 37, self.height / 2 - 20, 3, fill=1)
            canvas.circle(self.width / 2 + 37, self.height / 2 + 20, 3, fill=1)
            canvas.drawString(self.width / 2 - 48, self.height / 2 - 35, "P1")
            canvas.drawString(self.width / 2 + 42, self.height / 2 + 22, "P2")
        elif self.kind == "circle_circle":
            canvas.circle(self.width / 2 - 35, self.height / 2, 48, stroke=1, fill=0)
            canvas.circle(self.width / 2 + 35, self.height / 2, 48, stroke=1, fill=0)
            canvas.circle(self.width / 2, self.height / 2 + 34, 3, fill=1)
            canvas.circle(self.width / 2, self.height / 2 - 34, 3, fill=1)
            canvas.drawString(self.width / 2 + 8, self.height / 2 + 36, "P1")
            canvas.drawString(self.width / 2 + 8, self.height / 2 - 38, "P2")
        elif self.kind == "sector":
            cx = self.width / 2
            cy = self.height / 2 - 2
            radius = min(self.width, self.height) * 0.34
            canvas.wedge(cx - radius, cy - radius, cx + radius, cy + radius, 0, 70, stroke=1, fill=0)
            canvas.line(cx, cy, cx + radius, cy)
            canvas.line(cx, cy, cx + radius * cos(radians(70)), cy + radius * sin(radians(70)))
            canvas.drawString(cx + 8, cy + 10, "theta")
            canvas.drawString(cx + radius - 18, cy + 9, "r")
        elif self.kind == "network":
            pts = [(55, 35), (140, 90), (225, 42), (300, 94), (370, 36)]
            for a, b in zip(pts, pts[1:]):
                canvas.line(a[0], a[1], b[0], b[1])
            for index, (x, y) in enumerate(pts, start=1):
                canvas.circle(x, y, 4, fill=1)
                canvas.drawString(x + 6, y + 4, str(index))
        elif self.kind == "leveling":
            xs = [45, 115, 190, 270, 350]
            ys = [42, 64, 48, 76, 55]
            for idx, (x, y) in enumerate(zip(xs, ys), start=1):
                canvas.line(x, 20, x, y)
                canvas.circle(x, y, 4, fill=1)
                canvas.drawString(x - 7, 8, f"BM{idx}")
            canvas.line(xs[0], ys[0], xs[-1], ys[-1])
        canvas.restoreState()


def _q(section: str, title: str, prompt: str, solution: str, diagram: str | None = None) -> Question:
    return Question(section=section, title=title, prompt=prompt, solution=solution, diagram=diagram)


def build_intersection_questions() -> list[Question]:
    questions: list[Question] = []
    projection_cases = [
        ((6, 8), (0, 0), (10, 0)),
        ((5, 9), (1, 2), (9, 6)),
        ((12, 3), (2, 1), (2, 12)),
        ((4, 11), (0, 5), (12, 9)),
        ((9, 4), (3, 12), (15, 0)),
    ]
    for index, (p, a, b) in enumerate(projection_cases, 1):
        hx, hy, distance = project_point_to_line(p, a, b)
        questions.append(
            _q(
                "التقاطعات",
                f"إسقاط نقطة على مستقيم - نموذج {index}",
                f"النقطة P{p} والمستقيم AB حيث A{a} و B{b}. أوجد قدم العمود H والمسافة العمودية PH.",
                "نستخدم t = ((P-A).(B-A)) / |B-A|^2.\n"
                f"إذن H = ({fmt(hx)}, {fmt(hy)}) و PH = {fmt(distance)} m.\n"
                "إذا كان t بين 0 و 1 فالقدم داخل القطعة، وإلا فهو على امتدادها.",
                "projection" if index == 1 else None,
            )
        )

    line_cases = [
        ((0, 0), (10, 8), (0, 7), (12, 1)),
        ((2, 3), (14, 9), (1, 12), (13, 0)),
        ((0, 4), (16, 4), (9, 0), (9, 12)),
        ((3, 1), (15, 13), (4, 14), (14, 4)),
        ((2, 9), (13, 2), (0, 1), (14, 10)),
    ]
    for index, case in enumerate(line_cases, 1):
        p1, p2, p3, p4 = case
        ix, iy = line_intersection(p1, p2, p3, p4)
        questions.append(
            _q(
                "التقاطعات",
                f"تقاطع مستقيمين - نموذج {index}",
                f"أوجد نقطة تقاطع المستقيم الأول المار بالنقطتين {p1}, {p2} مع المستقيم الثاني المار بالنقطتين {p3}, {p4}.",
                "نكتب كل مستقيم في صورة بارامترية أو بصيغة المحددات.\n"
                f"ناتج التقاطع I = ({fmt(ix)}, {fmt(iy)}).\n"
                "تحقق سريع: عوض إحداثيات I في معادلتي المستقيمين.",
                "line_line" if index == 1 else None,
            )
        )

    line_circle_cases = [
        ((0, 0), (1, 1), (5, 5), sqrt(18)),
        ((0, 4), (1, 0), (6, 4), 3),
        ((2, 0), (0, 1), (2, 5), 4),
        ((0, 2), (2, 1), (6, 5), 5),
        ((1, 1), (3, 2), (7, 5), 4),
    ]
    for index, (point, direction, center, radius) in enumerate(line_circle_cases, 1):
        hits = line_circle_intersections(point, direction, center, radius)
        hit_text = " و ".join(f"({fmt(x)}, {fmt(y)})" for x, y in hits)
        questions.append(
            _q(
                "التقاطعات",
                f"تقاطع خط مع دائرة - نموذج {index}",
                f"الخط يمر بالنقطة {point} واتجاهه v={direction}. الدائرة مركزها C{center} ونصف قطرها r={fmt(radius)}. أوجد نقاط التقاطع.",
                "نعوض X = P + t v في معادلة الدائرة |X-C|^2 = r^2 ثم نحل المعادلة التربيعية في t.\n"
                f"نقاط التقاطع هي: {hit_text}.\n"
                "إذا كان المميز صفراً فالحل مماس، وإذا كان سالباً فلا يوجد تقاطع حقيقي.",
                "line_circle" if index == 1 else None,
            )
        )

    circle_cases = [
        ((0, 0), 5, (6, 0), 5),
        ((1, 2), 6, (9, 2), 4),
        ((0, 0), 10, (8, 6), 6),
        ((3, 1), 7, (11, 1), 5),
        ((2, 3), 8, (10, 7), 6),
    ]
    for index, (c1, r1, c2, r2) in enumerate(circle_cases, 1):
        hits = circle_circle_intersections(c1, r1, c2, r2)
        hit_text = " و ".join(f"({fmt(x)}, {fmt(y)})" for x, y in hits)
        questions.append(
            _q(
                "التقاطعات",
                f"تقاطع دائرتين - نموذج {index}",
                f"الدائرة الأولى مركزها {c1} ونصف قطرها {fmt(r1)}، والثانية مركزها {c2} ونصف قطرها {fmt(r2)}. أوجد نقطتي التقاطع.",
                "احسب d بين المركزين، ثم a = (r1^2-r2^2+d^2)/(2d)، و h = sqrt(r1^2-a^2).\n"
                f"نقطتا التقاطع هما: {hit_text}.\n"
                "تأكد من شرط التقاطع: |r1-r2| <= d <= r1+r2.",
                "circle_circle" if index == 1 else None,
            )
        )
    return questions


def build_error_questions() -> list[Question]:
    questions: list[Question] = []
    sector_cases = [
        (10, 60, 0.005, 5),
        (18, 72, 0.008, 8),
        (25, 40, 0.010, 6),
        (16, 95, 0.006, 10),
        (30, 35, 0.012, 12),
        (22, 110, 0.009, 7),
        (14, 125, 0.005, 9),
        (28, 80, 0.011, 5),
    ]
    for index, (radius, theta, sigma_r, sigma_theta) in enumerate(sector_cases, 1):
        result = circular_sector_metrics(radius, theta, sigma_r, sigma_theta)
        questions.append(
            _q(
                "نشر الأخطاء",
                f"قطاع دائري - مساحة ومحيط - نموذج {index}",
                f"قطاع دائري نصف قطره r={radius} m وزاويته theta={theta} degrees. إذا كان sigma_r={fmt(sigma_r * 1000, 1)} mm و sigma_theta={sigma_theta} seconds، احسب المساحة والمحيط والانحراف المعياري لكل منهما.",
                "حول الزاوية إلى راديان أولاً.\n"
                f"theta = {fmt(result['theta_rad'], 6)} rad.\n"
                f"A = 0.5 r^2 theta = {fmt(result['area_m2'])} m^2.\n"
                f"P = 2r + r theta = {fmt(result['perimeter_m'])} m.\n"
                "sigma_A = sqrt((r theta sigma_r)^2 + (0.5 r^2 sigma_theta)^2).\n"
                f"sigma_A = {fmt(result['sigma_area_m2'], 4)} m^2.\n"
                "sigma_P = sqrt(((2+theta) sigma_r)^2 + (r sigma_theta)^2).\n"
                f"sigma_P = {fmt(result['sigma_perimeter_m'], 4)} m.",
                "sector" if index == 1 else None,
            )
        )

    triangle_cases = [
        (42, 36, 63, 0.006, 0.005, 6),
        (55, 48, 72, 0.010, 0.008, 8),
        (30, 44, 51, 0.004, 0.006, 5),
        (62, 58, 38, 0.011, 0.009, 7),
        (75, 40, 84, 0.012, 0.006, 9),
    ]
    for index, (a, b, angle, sigma_a, sigma_b, sigma_angle) in enumerate(triangle_cases, 1):
        angle_rad = radians(angle)
        sigma_angle_rad = seconds_to_radians(sigma_angle)
        area = 0.5 * a * b * sin(angle_rad)
        sigma_area = sqrt(
            (0.5 * b * sin(angle_rad) * sigma_a) ** 2
            + (0.5 * a * sin(angle_rad) * sigma_b) ** 2
            + (0.5 * a * b * cos(angle_rad) * sigma_angle_rad) ** 2
        )
        questions.append(
            _q(
                "نشر الأخطاء",
                f"مساحة مثلث من ضلعين وزاوية - نموذج {index}",
                f"احسب مساحة مثلث من a={a} m و b={b} m والزاوية المحصورة C={angle} degrees. المعطى sigma_a={fmt(sigma_a*1000,1)} mm و sigma_b={fmt(sigma_b*1000,1)} mm و sigma_C={sigma_angle} seconds.",
                f"A = 0.5ab sin(C) = {fmt(area)} m^2.\n"
                "نشتق: dA/da = 0.5 b sin(C)، dA/db = 0.5 a sin(C)، dA/dC = 0.5ab cos(C).\n"
                f"sigma_A = {fmt(sigma_area, 4)} m^2.\n"
                "ملاحظة: خطأ الزاوية يدخل بالراديان، وليس بالدرجات.",
            )
        )

    precision_cases = [
        ("E50", 4.0, 120.0),
        ("E95", 8.0, 250.0),
        ("SD", 6.0, 80.0),
        ("E50", 2.5, 60.0),
        ("E95", 12.0, 310.0),
    ]
    for index, (precision_type, precision_mm, distance) in enumerate(precision_cases, 1):
        if precision_type == "E50":
            sigma_mm = precision_mm / 0.6745
        elif precision_type == "E95":
            sigma_mm = precision_mm / 1.96
        else:
            sigma_mm = precision_mm
        weight = 1.0 / (sigma_mm / 1000.0) ** 2
        questions.append(
            _q(
                "نشر الأخطاء",
                f"تحويل الدقة إلى وزن - نموذج {index}",
                f"رصد طول مقداره L={distance} m بدقة {precision_type}={precision_mm} mm. حول الدقة إلى sigma واحسب الوزن النسبي w=1/sigma^2.",
                f"sigma = {fmt(sigma_mm, 3)} mm = {fmt(sigma_mm/1000, 6)} m.\n"
                f"w = 1/sigma^2 = {fmt(weight, 1)}.\n"
                "في المقارنة بين أرصاد متعددة يكفي استعمال الأوزان النسبية إذا اتحدت الوحدات.",
            )
        )

    chain_cases = [
        ([45.32, 38.18, 22.40], [0.006, 0.005, 0.004]),
        ([80.10, 52.75, 31.06], [0.008, 0.006, 0.006]),
        ([12.50, 18.75, 26.25, 14.10], [0.003, 0.004, 0.004, 0.003]),
        ([60.00, 41.20, 19.80], [0.010, 0.006, 0.005]),
    ]
    for index, (lengths, sigmas) in enumerate(chain_cases, 1):
        total = sum(lengths)
        sigma_total = sqrt(sum(sigma * sigma for sigma in sigmas))
        lengths_text = ", ".join(fmt(value, 2) for value in lengths)
        sigmas_text = ", ".join(fmt(value * 1000, 1) for value in sigmas)
        questions.append(
            _q(
                "نشر الأخطاء",
                f"مجموع أطوال مستقلة - نموذج {index}",
                f"الأطوال المستقلة بالمتر هي: {lengths_text}. وانحرافاتها بالمليمتر هي: {sigmas_text}. احسب طول المسار وانحرافه المعياري.",
                f"L = sum Li = {fmt(total, 2)} m.\n"
                f"sigma_L = sqrt(sum sigma_i^2) = {fmt(sigma_total, 5)} m = {fmt(sigma_total*1000, 2)} mm.\n"
                "لا تجمع الانحرافات مباشرة؛ اجمع مربعاتها ثم خذ الجذر.",
            )
        )
    return questions


def build_adjustment_questions() -> list[Question]:
    questions: list[Question] = []
    direct_cases = [
        ([100.012, 100.018, 100.009], [0.004, 0.006, 0.004]),
        ([53.214, 53.220, 53.208, 53.216], [0.005, 0.005, 0.008, 0.004]),
        ([250.31, 250.27, 250.34], [0.02, 0.03, 0.02]),
        ([18.506, 18.498, 18.511, 18.503], [0.003, 0.004, 0.003, 0.005]),
        ([72.44, 72.51, 72.48], [0.04, 0.03, 0.05]),
        ([11.208, 11.214, 11.211], [0.002, 0.004, 0.003]),
    ]
    for index, (values, sigmas) in enumerate(direct_cases, 1):
        result = weighted_mean(values, sigmas)
        values_text = ", ".join(fmt(value, 3) for value in values)
        sigmas_text = ", ".join(fmt(value, 3) for value in sigmas)
        questions.append(
            _q(
                "الضبط والمربعات الصغرى",
                f"متوسط موزون لرصد مباشر - نموذج {index}",
                f"للكمية X أرصاد مستقلة: {values_text}. الانحرافات المعيارية: {sigmas_text} m. أوجد X المضبوط.",
                "نستخدم P = diag(1/sigma_i^2) و Xhat = sum(Pi Li) / sum(Pi).\n"
                f"Xhat = {fmt(result['mean'], 4)} m.\n"
                f"sigma_Xhat = sqrt(1/sum(Pi)) = {fmt(result['sigma_mean'], 5)} m.",
            )
        )

    angle_cases = [
        (3, [59.999, 60.004, 59.994]),
        (4, [89.998, 90.010, 89.992, 89.997]),
        (5, [108.010, 107.995, 108.002, 107.990, 108.006]),
        (6, [119.990, 120.006, 120.004, 119.997, 120.002, 120.001]),
    ]
    for index, (n, angles) in enumerate(angle_cases, 1):
        theoretical = (n - 2) * 180.0
        observed = sum(angles)
        misclosure = observed - theoretical
        correction = -misclosure / n
        questions.append(
            _q(
                "الضبط والمربعات الصغرى",
                f"شرط مجموع زوايا مضلع - نموذج {index}",
                f"مضلع عدد أضلاعه n={n}. الزوايا المرصودة بالدرجات: {', '.join(fmt(a,3) for a in angles)}. اكتب معادلة الشرط ووزع التصحيح بالتساوي.",
                f"معادلة الشرط: sum beta_i - (n-2)180 = 0.\n"
                f"sum beta_i = {fmt(observed, 3)} degrees، والقيمة النظرية = {fmt(theoretical, 3)} degrees.\n"
                f"f = observed - theoretical = {fmt(misclosure, 3)} degrees.\n"
                f"تصحيح كل زاوية = {-fmt(misclosure, 3) if False else fmt(correction, 4)} degrees.",
            )
        )

    closure_cases = [
        ([42.5, 35.0, -20.5, -56.7], [12.1, 38.2, 30.0, -80.6]),
        ([15.2, 44.8, -33.1, -26.4], [25.5, -10.2, 31.7, -46.4]),
        ([60.0, -12.5, -22.2, -24.8], [8.0, 42.1, -18.4, -31.2]),
    ]
    for index, (latitudes, departures) in enumerate(closure_cases, 1):
        fy = sum(latitudes)
        fx = sum(departures)
        questions.append(
            _q(
                "الضبط والمربعات الصغرى",
                f"شرطا قفل إحداثي - نموذج {index}",
                f"في مضلع مغلق كانت فروق الشماليات: {', '.join(fmt(v,1) for v in latitudes)}، وفروق الشرقيات: {', '.join(fmt(v,1) for v in departures)}. اكتب شرطي القفل وقيمتي عدم القفل.",
                "شرطا القفل في المضلع المغلق: sum DeltaN = 0 و sum DeltaE = 0.\n"
                f"f_N = {fmt(fy, 3)} m، و f_E = {fmt(fx, 3)} m.\n"
                f"خطأ القفل الخطي = sqrt(f_N^2+f_E^2) = {fmt(hypot(fy, fx), 3)} m.",
            )
        )

    line_fit_cases = [
        [(0, 1.1), (1, 2.9), (2, 5.2), (3, 7.1)],
        [(1, 4.0), (2, 6.1), (4, 10.2), (5, 12.1)],
        [(0, 3.2), (2, 5.0), (3, 6.7), (6, 9.9)],
    ]
    for index, points in enumerate(line_fit_cases, 1):
        n = len(points)
        sx = sum(x for x, _ in points)
        sy = sum(y for _, y in points)
        sxx = sum(x * x for x, _ in points)
        sxy = sum(x * y for x, y in points)
        denominator = n * sxx - sx * sx
        b = (n * sxy - sx * sy) / denominator
        a = (sy - b * sx) / n
        questions.append(
            _q(
                "الضبط والمربعات الصغرى",
                f"ملاءمة خط y=a+bx - نموذج {index}",
                f"النقاط المرصودة هي: {points}. كوّن معادلات الرصد واحسب a و b بطريقة المربعات الصغرى.",
                "معادلات الرصد: y_i = a + b x_i + v_i، ومصفوفة التصميم صفها [1, x_i].\n"
                f"بعد حساب المجاميع: a = {fmt(a, 3)}، b = {fmt(b, 3)}.\n"
                "اكتب N=A^T A و U=A^T L ثم X=(N^-1)U إذا طُلب الحل المصفوفي.",
            )
        )

    ordered_network_prompts = [
        (
            "شبكة زوايا مرقمة من 1 إلى 11 حول مضلع خماسي.",
            "ابدأ بالشرط العام للمضلع: C1: sum beta_1..beta_5 - 540 = 0، ثم شروط المثلثات الداخلية، ثم شروط الاتجاهات المتتابعة. حافظ على نفس ترتيب الأرقام في الرسم.",
        ),
        (
            "شبكة اتجاهات مرقمة من 1 إلى 12 وفيها ثلاث مثلثات ومضلع خارجي.",
            "اكتب أولاً شروط كل مثلث: مجموع الزوايا - 180 = 0، ثم شرط المضلع الخارجي، ثم شروط الزوايا المشتركة. الناتج المتوقع 11 أو 12 معادلة حسب عدد القيود المستقلة.",
        ),
    ]
    for index, (prompt, solution) in enumerate(ordered_network_prompts, 1):
        questions.append(
            _q(
                "الضبط والمربعات الصغرى",
                f"تكوين معادلات شرطية بترتيب الرسم - نموذج {index}",
                f"{prompt} المطلوب: اكتب منهج تكوين المعادلات بدون تغيير ترتيب الأرقام.",
                f"{solution}\n"
                "قاعدة الامتحان: امش مع الرسم من الرقم 1 ثم 2 ثم 3، لأن الترتيب جزء من سهولة السؤال.",
                "network" if index == 1 else None,
            )
        )
    return questions


def build_leveling_questions() -> list[Question]:
    questions: list[Question] = []
    leveling_cases = [
        (150.000, [0.85, 1.25, 0.74], [1.10, 0.95, 1.04], 149.75, [0.4, 0.6, 0.5]),
        (50.000, [1.40, 0.82, 1.15], [0.92, 1.26, 1.04], 50.18, [0.7, 0.5, 0.6]),
        (125.500, [0.62, 1.05, 0.91, 1.20], [0.75, 0.88, 1.10, 0.96], 125.62, [0.3, 0.4, 0.5, 0.6]),
        (80.250, [1.22, 0.97, 0.66], [0.84, 1.13, 0.70], 80.45, [0.5, 0.5, 0.4]),
        (200.000, [0.55, 0.79, 1.31, 0.64], [0.73, 0.68, 1.05, 0.86], 199.96, [0.8, 0.7, 0.6, 0.5]),
    ]
    for index, (start, backsights, foresights, known_end, lengths) in enumerate(leveling_cases, 1):
        observed_end = start + sum(backsights) - sum(foresights)
        misclosure = observed_end - known_end
        total_length = sum(lengths)
        corrections = [-(misclosure) * length / total_length for length in lengths]
        questions.append(
            _q(
                "الميزانية والأوزان",
                f"ميزانية تفاضلية وتوزيع خطأ القفل - نموذج {index}",
                f"منسوب البداية BM={fmt(start,3)} m. قراءات BS: {', '.join(fmt(v,2) for v in backsights)}، و FS: {', '.join(fmt(v,2) for v in foresights)}. منسوب النهاية المعلوم {fmt(known_end,3)} m، وأطوال المقاطع km: {', '.join(fmt(v,1) for v in lengths)}. احسب خطأ القفل ووزع التصحيح.",
                f"المنسوب المرصود للنهاية = BM + sum(BS) - sum(FS) = {fmt(observed_end,3)} m.\n"
                f"خطأ القفل f = observed - known = {fmt(misclosure,4)} m.\n"
                f"التصحيحات حسب الأطوال: {', '.join(fmt(v,4) for v in corrections)} m.\n"
                "بعد التصحيح يجب أن تصبح النهاية مساوية للمنسوب المعلوم.",
                "leveling" if index == 1 else None,
            )
        )

    weighted_level_cases = [
        ([150.12, 150.18, 150.10], [0.02, 0.04, 0.02]),
        ([49.95, 50.02, 50.00, 49.98], [0.03, 0.02, 0.02, 0.04]),
        ([125.62, 125.58, 125.64], [0.05, 0.03, 0.04]),
        ([80.31, 80.29, 80.36, 80.30], [0.02, 0.02, 0.05, 0.03]),
        ([200.11, 200.04, 200.08], [0.04, 0.03, 0.02]),
    ]
    for index, (values, sigmas) in enumerate(weighted_level_cases, 1):
        result = weighted_mean(values, sigmas)
        questions.append(
            _q(
                "الميزانية والأوزان",
                f"منسوب موزون من عدة مسارات - نموذج {index}",
                f"حُسب منسوب نقطة من عدة مسارات: {', '.join(fmt(v,3) for v in values)} m. انحرافات المسارات: {', '.join(fmt(s,3) for s in sigmas)} m. أوجد المنسوب النهائي الموزون.",
                f"H = sum(w_i H_i)/sum(w_i) = {fmt(result['mean'],4)} m.\n"
                f"sigma_H = sqrt(1/sum(w_i)) = {fmt(result['sigma_mean'],4)} m.\n"
                "إذا كانت كل النتائج حول نفس الرينج فهذا مؤشر هندسي جيد، لكن القرار النهائي بالحساب.",
            )
        )
    return questions


def build_poetry_questions() -> list[Question]:
    data = [
        (
            "من هو الشاعر المقصود بالشاعر الثالث من الأندلس في المراجعة؟",
            "المقصود غالباً أبو البقاء الرندي، صاحب القصيدة المشهورة في رثاء الأندلس.",
        ),
        (
            "ما الفكرة العامة في مطلع قصيدة البكاء الرندي؟",
            "الفكرة أن الكمال في الدنيا لا يدوم، وأن النقص والتغير سنة جارية على الأشياء.",
        ),
        (
            "اشرح معنى: لكل شيء إذا ما تم نقصان.",
            "أي أن كل أمر إذا بلغ تمامه بدأ يتعرض للنقص والزوال، فلا بقاء لحال الدنيا.",
        ),
        (
            "ما نوع الأسلوب في تذكير الشاعر بزوال الدول والحضارات؟",
            "أسلوب وعظ وتنبيه، وفيه تقرير لحقيقة تاريخية لإثارة الاعتبار والحزن.",
        ),
        (
            "ما معنى كلمة نقصان في سياق البيت؟",
            "النقص بعد الكمال، أو بداية التراجع بعد بلوغ الشيء تمامه.",
        ),
        (
            "أعرب كلمة شيء في عبارة: لكل شيء.",
            "اسم مجرور باللام وعلامة جره الكسرة، وهو مضاف إليه معنى داخل شبه الجملة.",
        ),
        (
            "ما سبب تسمية القصيدة بالبكاء الرندي؟",
            "لأنها قصيدة رثاء حزينة للأندلس، كتبها الرندي مستنهضاً ومتحسراً على ضياع المدن.",
        ),
        (
            "كيف تذاكر سؤال الشعر إذا كان عليه درجة ونصف فقط؟",
            "احفظ اسم الشاعر، مطلع القصيدة، معاني الكلمات الأساسية، وفكرة الرثاء والاعتبار، ولا تأخذ من وقت مسائل الحساب.",
        ),
    ]
    return [_q("الشعر", f"البكاء الرندي - سؤال {index}", prompt, solution) for index, (prompt, solution) in enumerate(data, 1)]


def build_mixed_drills() -> list[Question]:
    return [
        _q(
            "تدريبات مختلطة",
            "تدريب شامل سريع - نموذج 1",
            "حل الأجزاء الآتية في 25 دقيقة:\n"
            "1. أسقط P(8,6) على الخط A(0,0)-B(12,0).\n"
            "2. احسب قطاعاً دائرياً r=12 m و theta=75 degrees مع sigma_r=4 mm و sigma_theta=6 seconds.\n"
            "3. اكتب شرط مجموع زوايا مضلع خماسي.\n"
            "4. وزع خطأ قفل ميزانية مقداره +0.030 m على مقاطع أطوالها 0.5, 0.7, 0.8 km.\n"
            "5. اذكر شاعر البكاء الرندي.",
            "1. H=(8,0) و PH=6 m.\n"
            "2. theta=1.308997 rad، A=94.248 m^2، P=39.708 m، sigma_A=0.0629 m^2 تقريباً، sigma_P=0.0132 m.\n"
            "3. sum beta_i - 540 = 0.\n"
            "4. التصحيحات = -0.0075, -0.0105, -0.0120 m.\n"
            "5. أبو البقاء الرندي.",
        ),
        _q(
            "تدريبات مختلطة",
            "تدريب شامل سريع - نموذج 2",
            "حل الأجزاء الآتية في 25 دقيقة:\n"
            "1. أوجد تقاطع الخطين A(0,0)-B(10,10) و C(0,8)-D(8,0).\n"
            "2. حول E95=9.8 mm إلى sigma.\n"
            "3. أرصاد منسوب: 50.10, 50.16, 50.12 وانحرافاتها 0.02, 0.04, 0.02 m. أوجد المتوسط الموزون.\n"
            "4. اكتب شرطي قفل الإحداثيات في مضلع مغلق.\n"
            "5. ما معنى نقصان في مطلع القصيدة؟",
            "1. I=(4,4).\n"
            "2. sigma = 9.8/1.96 = 5.0 mm.\n"
            "3. H = 50.12 m و sigma_H = 0.0133 m.\n"
            "4. sum DeltaE=0 و sum DeltaN=0.\n"
            "5. التراجع أو النقص بعد بلوغ الكمال.",
        ),
    ]


def build_question_bank() -> list[Question]:
    questions = []
    questions.extend(build_intersection_questions())
    questions.extend(build_error_questions())
    questions.extend(build_adjustment_questions())
    questions.extend(build_leveling_questions())
    questions.extend(build_poetry_questions())
    questions.extend(build_mixed_drills())
    return questions


def register_fonts() -> tuple[str, str]:
    regular = Path(r"C:\Windows\Fonts\tahoma.ttf")
    bold = Path(r"C:\Windows\Fonts\tahomabd.ttf")
    if not regular.exists():
        regular = Path(r"C:\Windows\Fonts\arial.ttf")
    if not bold.exists():
        bold = Path(r"C:\Windows\Fonts\arialbd.ttf")
    if regular.exists() and bold.exists():
        pdfmetrics.registerFont(TTFont("ArabicRegular", str(regular)))
        pdfmetrics.registerFont(TTFont("ArabicBold", str(bold)))
        return "ArabicRegular", "ArabicBold"
    return "Helvetica", "Helvetica-Bold"


def make_styles(font_name: str, bold_font: str) -> dict[str, ParagraphStyle]:
    sample = getSampleStyleSheet()
    return {
        "cover_title": ParagraphStyle(
            "cover_title",
            parent=sample["Title"],
            fontName=bold_font,
            fontSize=24,
            leading=34,
            alignment=TA_CENTER,
            textColor=colors.HexColor("#1f3a4d"),
        ),
        "cover_subtitle": ParagraphStyle(
            "cover_subtitle",
            parent=sample["Normal"],
            fontName=font_name,
            fontSize=13,
            leading=22,
            alignment=TA_CENTER,
            textColor=colors.HexColor("#263238"),
        ),
        "h1": ParagraphStyle(
            "h1",
            parent=sample["Heading1"],
            fontName=bold_font,
            fontSize=16,
            leading=24,
            alignment=TA_RIGHT,
            spaceBefore=8,
            spaceAfter=8,
            textColor=colors.HexColor("#1f3a4d"),
        ),
        "h2": ParagraphStyle(
            "h2",
            parent=sample["Heading2"],
            fontName=bold_font,
            fontSize=12,
            leading=18,
            alignment=TA_RIGHT,
            textColor=colors.white,
        ),
        "body": ParagraphStyle(
            "body",
            parent=sample["BodyText"],
            fontName=font_name,
            fontSize=10.3,
            leading=16,
            alignment=TA_RIGHT,
            textColor=colors.HexColor("#222222"),
        ),
        "solution": ParagraphStyle(
            "solution",
            parent=sample["BodyText"],
            fontName=font_name,
            fontSize=9.5,
            leading=14.5,
            alignment=TA_RIGHT,
            textColor=colors.HexColor("#263238"),
        ),
        "formula": ParagraphStyle(
            "formula",
            parent=sample["BodyText"],
            fontName="Courier",
            fontSize=8.5,
            leading=12,
            alignment=TA_LEFT,
            textColor=colors.HexColor("#1a1a1a"),
        ),
        "small": ParagraphStyle(
            "small",
            parent=sample["BodyText"],
            fontName=font_name,
            fontSize=8.5,
            leading=12,
            alignment=TA_RIGHT,
            textColor=colors.HexColor("#555555"),
        ),
    }


def para(text: str, style: ParagraphStyle) -> Paragraph:
    return Paragraph(display_text(text), style)


def boxed_paragraph(
    text: str,
    style: ParagraphStyle,
    width: float,
    background: colors.Color,
    border: colors.Color = colors.HexColor("#d5dde5"),
    padding: int = 7,
) -> Table:
    table = Table([[para(text, style)]], colWidths=[width])
    table.setStyle(
        TableStyle(
            [
                ("BACKGROUND", (0, 0), (-1, -1), background),
                ("BOX", (0, 0), (-1, -1), 0.5, border),
                ("LEFTPADDING", (0, 0), (-1, -1), padding),
                ("RIGHTPADDING", (0, 0), (-1, -1), padding),
                ("TOPPADDING", (0, 0), (-1, -1), padding),
                ("BOTTOMPADDING", (0, 0), (-1, -1), padding),
            ]
        )
    )
    return table


def formula_sheet(styles: dict[str, ParagraphStyle], width: float) -> list:
    formulas = [
        "قطاع دائري: theta(rad)=theta(deg)*pi/180, A=0.5*r^2*theta, P=2r+r*theta",
        "نشر الأخطاء: sigma_f=sqrt(sum((df/dx_i * sigma_i)^2))",
        "الثواني إلى راديان: sigma_rad = seconds*pi/(180*3600)",
        "E50 = 0.6745*sigma, E95 = 1.96*sigma, w = 1/sigma^2",
        "المتوسط الموزون: Xhat = sum(w_i*L_i)/sum(w_i), sigma_X=sqrt(1/sum(w_i))",
        "تقاطع خط ودائرة: X=P+t*v ثم |X-C|^2=r^2",
        "مضلع مغلق: sum(DeltaE)=0, sum(DeltaN)=0, sum(beta)-(n-2)*180=0",
        "ميزانية: H_end = H_start + sum(BS) - sum(FS)",
    ]
    rows = [[para(item, styles["body"])] for item in formulas]
    table = Table(rows, colWidths=[width])
    table.setStyle(
        TableStyle(
            [
                ("BACKGROUND", (0, 0), (-1, -1), colors.HexColor("#f8fafc")),
                ("BOX", (0, 0), (-1, -1), 0.6, colors.HexColor("#c9d5df")),
                ("INNERGRID", (0, 0), (-1, -1), 0.3, colors.HexColor("#dfe7ee")),
                ("LEFTPADDING", (0, 0), (-1, -1), 8),
                ("RIGHTPADDING", (0, 0), (-1, -1), 8),
                ("TOPPADDING", (0, 0), (-1, -1), 6),
                ("BOTTOMPADDING", (0, 0), (-1, -1), 6),
            ]
        )
    )
    return [para("ورقة القوانين السريعة", styles["h1"]), table]


def render_question(question: Question, number: int, styles: dict[str, ParagraphStyle], width: float) -> list:
    parts = [
        boxed_paragraph(
            f"س{number}: {question.title}",
            styles["h2"],
            width,
            colors.HexColor("#2f4f68"),
            colors.HexColor("#2f4f68"),
            padding=6,
        ),
        boxed_paragraph(
            question.prompt,
            styles["body"],
            width,
            colors.white,
            colors.HexColor("#d9e1e8"),
            padding=7,
        ),
    ]
    if question.diagram:
        parts.extend([Spacer(1, 3), Sketch(question.diagram, width=width, height=3.0 * cm)])
    parts.extend(
        [
            boxed_paragraph(
                "الحل:\n" + question.solution,
                styles["solution"],
                width,
                colors.HexColor("#f2f7f3"),
                colors.HexColor("#b9d3bf"),
                padding=7,
            ),
            Spacer(1, 7),
        ]
    )
    return parts


def grouped_questions(questions: Iterable[Question]) -> dict[str, list[Question]]:
    grouped: dict[str, list[Question]] = defaultdict(list)
    for question in questions:
        grouped[question.section].append(question)
    return grouped


def draw_page_frame(canvas, doc) -> None:
    canvas.saveState()
    width, height = A4
    canvas.setStrokeColor(colors.HexColor("#d7e0e7"))
    canvas.setLineWidth(0.5)
    canvas.line(1.3 * cm, 1.25 * cm, width - 1.3 * cm, 1.25 * cm)
    canvas.setFont("ArabicRegular", 8)
    canvas.setFillColor(colors.HexColor("#5b6b76"))
    canvas.drawString(1.35 * cm, 0.83 * cm, f"Page {doc.page}")
    header = rtl("بنك الأسئلة المتوقع - المساحة الهندسية 2")
    canvas.drawRightString(width - 1.35 * cm, 0.83 * cm, header)
    canvas.restoreState()


def build_pdf(output_path: Path = OUTPUT_PDF) -> Path:
    output_path.parent.mkdir(parents=True, exist_ok=True)
    font_name, bold_font = register_fonts()
    styles = make_styles(font_name, bold_font)
    doc = SimpleDocTemplate(
        str(output_path),
        pagesize=A4,
        rightMargin=1.35 * cm,
        leftMargin=1.35 * cm,
        topMargin=1.25 * cm,
        bottomMargin=1.55 * cm,
        title="Arabic Surveying Question Bank",
        author="Codex",
    )
    width = doc.width
    story = [
        Spacer(1, 1.2 * cm),
        para("بنك الأسئلة المتوقع", styles["cover_title"]),
        para("المساحة الهندسية 2 - Adjustment Computations & Coordinate Geometry", styles["cover_subtitle"]),
        Spacer(1, 0.8 * cm),
        boxed_paragraph(
            "ملف مراجعة مركز مبني على نمط الامتحانات السابقة وتسريبات المراجعة: التقاطعات، نشر الأخطاء، المربعات الصغرى، الميزانية، وسؤال الشعر.",
            styles["body"],
            width,
            colors.HexColor("#eef5f8"),
            colors.HexColor("#c7d9e3"),
            padding=12,
        ),
        Spacer(1, 0.35 * cm),
        boxed_paragraph(
            "استراتيجية الحل: ابدأ بالتقاطعات والميزانية لأنها مباشرة، ثم المربعات والمعادلات، واترك مسألة التفاضل الطويلة لآخر الوقت إذا كانت ستأخذ كتابة كثيرة.",
            styles["body"],
            width,
            colors.HexColor("#fff8e8"),
            colors.HexColor("#e2c66d"),
            padding=12,
        ),
        Spacer(1, 0.5 * cm),
    ]
    story.extend(formula_sheet(styles, width))
    story.append(PageBreak())

    questions = build_question_bank()
    grouped = grouped_questions(questions)
    order = [
        "التقاطعات",
        "نشر الأخطاء",
        "الضبط والمربعات الصغرى",
        "الميزانية والأوزان",
        "الشعر",
        "تدريبات مختلطة",
    ]
    number = 1
    for section in order:
        story.append(para(section, styles["h1"]))
        intro = {
            "التقاطعات": "أسئلة مباشرة من نوع إسقاط نقطة، تقاطع مستقيمين، خط مع دائرة، ودائرتين. ركز على الصيغة ثم التعويض.",
            "نشر الأخطاء": "كل سؤال هنا يختبر التفاضل والتحويل الصحيح للزوايا إلى راديان، خصوصاً القطاع الدائري.",
            "الضبط والمربعات الصغرى": "المطلوب غالباً تكوين المعادلات بترتيب الرسم أو حساب متوسط موزون بسيط.",
            "الميزانية والأوزان": "راقب رينج المناسيب وخطأ القفل، ثم وزع التصحيحات حسب الأطوال أو الأوزان.",
            "الشعر": "أسئلة قصيرة للمراجعة السريعة حتى لا تضيع الدرجة السهلة.",
            "تدريبات مختلطة": "محاكاة مختصرة لطريقة التنقل بين الأسئلة داخل وقت الامتحان.",
        }[section]
        story.append(boxed_paragraph(intro, styles["small"], width, colors.HexColor("#f6f8fa"), padding=6))
        story.append(Spacer(1, 6))
        for question in grouped[section]:
            story.extend(render_question(question, number, styles, width))
            number += 1
        if section != order[-1]:
            story.append(PageBreak())

    doc.build(story, onFirstPage=draw_page_frame, onLaterPages=draw_page_frame)
    return output_path


def main() -> None:
    path = build_pdf()
    print(path)


if __name__ == "__main__":
    main()
