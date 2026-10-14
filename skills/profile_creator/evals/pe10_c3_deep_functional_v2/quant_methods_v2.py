"""Pure, read-only decision mathematics for LF shadow benchmark, never a promoter.

Assumes independent Bernoulli complaints and a declared Beta prior for illustration.
A statistical bound is not a business approval or proof of causal efficacy.
"""
from __future__ import annotations
import math
from statistics import NormalDist

def _valid_count(x):
    return type(x) is int and x >= 0

def _betacf(a:float,b:float,x:float)->float:
    # Continued fraction (Numerical Recipes). No scipy/runtime network dependency.
    qab=a+b; qap=a+1.0; qam=a-1.0
    c=1.0; d=1.0-qab*x/qap
    tiny=1e-300
    if abs(d)<tiny:d=tiny
    d=1.0/d;h=d
    for m in range(1,1001):
        m2=2*m
        aa=m*(b-m)*x/((qam+m2)*(a+m2))
        d=1.0+aa*d
        if abs(d)<tiny:d=tiny
        c=1.0+aa/c
        if abs(c)<tiny:c=tiny
        d=1.0/d;h*=d*c
        aa=-(a+m)*(qab+m)*x/((a+m2)*(qap+m2))
        d=1.0+aa*d
        if abs(d)<tiny:d=tiny
        c=1.0+aa/c
        if abs(c)<tiny:c=tiny
        d=1.0/d;step=d*c;h*=step
        if abs(step-1.0)<2e-13:return h
    raise ArithmeticError("BETA_CONTINUED_FRACTION_NONCONVERGENCE")

def _beta_cdf(x:float,a:float,b:float)->float:
    if x<=0:return 0.0
    if x>=1:return 1.0
    bt=math.exp(math.lgamma(a+b)-math.lgamma(a)-math.lgamma(b)+a*math.log(x)+b*math.log1p(-x))
    if x<(a+1)/(a+b+2):
        return min(1.0,max(0.0,bt*_betacf(a,b,x)/a))
    return min(1.0,max(0.0,1.0-bt*_betacf(b,a,1-x)/b))

def beta_sf(x:float,a:float,b:float)->float:
    # Evaluate complement directly in upper region to avoid catastrophic subtraction.
    if x<=0:return 1.0
    if x>=1:return 0.0
    bt=math.exp(math.lgamma(a+b)-math.lgamma(a)-math.lgamma(b)+a*math.log(x)+b*math.log1p(-x))
    if x<(a+1)/(a+b+2):
        return max(0.0,min(1.0,1.0-bt*_betacf(a,b,x)/a))
    return max(0.0,min(1.0,bt*_betacf(b,a,1-x)/b))

def beta_upper_quantile(prob:float,a:float,b:float)->float:
    if not 0<prob<1:raise ValueError("PROBABILITY_INVALID")
    lo=0.0;hi=1.0
    for _ in range(75):
        mid=(lo+hi)/2
        if _beta_cdf(mid,a,b)<prob:lo=mid
        else:hi=mid
    return (lo+hi)/2

def complaints_risk(*,events:int,exposures:int,limit:float,prior_a:float=1.0,prior_b:float=1.0)->dict:
    if not(_valid_count(events) and _valid_count(exposures) and exposures>0 and events<=exposures):
        raise ValueError("BERNOULLI_COUNTS_INVALID")
    if type(limit) not in (float,int) or not 0<limit<1 or min(prior_a,prior_b)<=0:
        raise ValueError("RISK_PARAMETERS_INVALID")
    a=events+prior_a;b=exposures-events+prior_b
    p=events/exposures
    z=NormalDist().inv_cdf(.975)
    center=(p+z*z/(2*exposures))/(1+z*z/exposures)
    half=z*math.sqrt(p*(1-p)/exposures+z*z/(4*exposures**2))/(1+z*z/exposures)
    return {
        "events":events,"exposures":exposures,"observed_rate":p,
        "guardrail":limit,"observed_guardrail_exceeded":p>limit,
        "wilson_upper95":center+half,
        "bayesian_prior":{"alpha":prior_a,"beta":prior_b},
        "posterior":{"alpha":a,"beta":b},
        "posterior_pr_exceeds_guardrail":beta_sf(limit,a,b),
        "posterior_upper95":beta_upper_quantile(.95,a,b),
        "source_status":"COUNTS_SUPPLIED_NOT_EXTERNALLY_VERIFIED",
        "claim_limit":"CONDITIONAL_MODEL_ESTIMATE_NOT_CAUSAL_PROOF_OR_AUTHORIZATION"
    }

def allocation_balance(*,control:int,treatment:int,expected_treatment_fraction:float=.5)->dict:
    if not (_valid_count(control) and _valid_count(treatment)) or control+treatment<2:
        raise ValueError("ALLOCATION_COUNTS_INVALID")
    if type(expected_treatment_fraction) not in (float,int) or not 0<expected_treatment_fraction<1:
        raise ValueError("ALLOCATION_FRACTION_INVALID")
    n=control+treatment;np=n*expected_treatment_fraction
    z=(treatment-np)/math.sqrt(n*expected_treatment_fraction*(1-expected_treatment_fraction))
    p=math.erfc(abs(z)/math.sqrt(2))
    return {"n":n,"treatment":treatment,"control":control,
            "expected_treatment_fraction":expected_treatment_fraction,
            "z_normal_approximation":z,"p_value_two_sided_normal_approximation":p,
            "small_p_warning":p<.001,
            "causal_claim_allowed":False,
            "claim_limit":"SRM screen; investigate logging/randomization before causal lift interpretation"}

def expected_net(*,paid_amount:float,probability_paid:float,cost:float,complaint_probability:float,complaint_cost:float,
                 other_cost:float=0.0)->dict:
    vals=(paid_amount,probability_paid,cost,complaint_probability,complaint_cost,other_cost)
    if any(type(x) not in (float,int) or not math.isfinite(x) for x in vals):
        raise ValueError("CASH_VALUES_INVALID")
    if any(x<0 for x in (paid_amount,cost,complaint_cost,other_cost)) or not 0<=probability_paid<=1 or not 0<=complaint_probability<=1:
        raise ValueError("CASH_PARAMETERS_INVALID")
    payment=paid_amount*probability_paid
    complaint_loss=complaint_probability*complaint_cost
    return {"expected_collected":payment,"expected_complaint_cost":complaint_loss,
            "expected_net":payment-complaint_loss-cost-other_cost,
            "assumption":"LINEAR_EXPECTED_VALUE_NO_CAUSAL_IDENTIFICATION",
            "source_status":"PARAMETERS_SUPPLIED_NOT_OBSERVED_BY_FUNCTION"}
