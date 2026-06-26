from collections import Counter
from math import pi

import pytest

from scripts.generate_surveying_question_bank_pdf import (
    build_question_bank,
    circular_sector_metrics,
    weighted_mean,
)


def test_circular_sector_metrics_uses_radians_and_seconds():
    result = circular_sector_metrics(
        radius_m=10.0,
        theta_deg=60.0,
        sigma_radius_m=0.005,
        sigma_theta_seconds=5.0,
    )

    assert result["theta_rad"] == pytest.approx(pi / 3, rel=1e-12)
    assert result["area_m2"] == pytest.approx(52.35987756, rel=1e-8)
    assert result["perimeter_m"] == pytest.approx(30.47197551, rel=1e-8)
    assert result["sigma_area_m2"] == pytest.approx(0.052374, rel=1e-4)
    assert result["sigma_perimeter_m"] == pytest.approx(0.015238, rel=1e-4)


def test_weighted_mean_uses_inverse_variance_weights():
    result = weighted_mean(
        values=[150.12, 150.18, 150.10],
        sigmas=[0.02, 0.04, 0.02],
    )

    assert result["mean"] == pytest.approx(150.1177777778, rel=1e-10)
    assert result["sigma_mean"] == pytest.approx(0.0133333333, rel=1e-8)


def test_question_bank_matches_requested_scope():
    questions = build_question_bank()
    counts = Counter(question.section for question in questions)

    assert len(questions) == 80
    assert counts["التقاطعات"] == 20
    assert counts["نشر الأخطاء"] == 22
    assert counts["الضبط والمربعات الصغرى"] == 18
    assert counts["الميزانية والأوزان"] == 10
    assert counts["الشعر"] == 8
    assert counts["تدريبات مختلطة"] == 2
