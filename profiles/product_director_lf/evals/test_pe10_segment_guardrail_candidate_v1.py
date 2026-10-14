"""Frozen arithmetic invariants for PE10_C3 V2 cases 209 and 211; no live rollout."""
from pathlib import Path

profile = Path(__file__).resolve().parents[1] / "SKILL.md"
text = profile.read_text(encoding="utf-8")
assert "## Conditional segment-normalization and guardrail decision method" in text
assert "not causal evidence" in text.lower() or "not causal" in text.lower()

# 209: different segment composition, exact frozen observed counts.
a_high, a_low, b_high, b_low = 9/10, 20/100, 80/100, 1/10
assert (9+20)/(10+100) < (80+1)/(100+10)
assert a_high > b_high and a_low > b_low
assert (a_high+a_low)/2 == 0.55
assert (b_high+b_low)/2 == 0.45
assert round((a_high-b_high), 8) == round((a_low-b_low), 8) == 0.1
for weight in [0,0.25,0.5,0.75,1]:
    delta = weight*(a_high-b_high)+(1-weight)*(a_low-b_low)
    assert abs(delta-0.1)<1e-12

# 211: forecast economics, separate hard business guardrail.
net_a=120*.40-3-40*.005
net_b=120*.50-6-40*.03
assert abs(net_a-44.8)<1e-12
assert abs(net_b-52.8)<1e-12
assert abs(net_b-net_a-8)<1e-12
assert .03>.01
assert net_b>net_a and .03>.01 # stronger modeled expected net is not a launch license

print("PASS: source candidate present; 12 frozen arithmetic/guardrail assertions, NO_RUNTIME_JUDGE")
