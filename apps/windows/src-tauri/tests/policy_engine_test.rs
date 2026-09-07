use focusguard_windows::domain::device::DeviceStatus;
use focusguard_windows::domain::policy::{evaluate, PolicyDecision};

#[test]
fn test_policy_engine_matrix() {
    let active = DeviceStatus::Active;

    // 0 / 30 mins (1800s) -> ALLOW
    assert_eq!(
        evaluate(0, 1800, 1500, &active),
        PolicyDecision::Allow,
        "0 usage must be ALLOW"
    );

    // 24 / 30 mins (1440s / 1800s, warn at 1500s) -> ALLOW
    assert_eq!(
        evaluate(1440, 1800, 1500, &active),
        PolicyDecision::Allow,
        "24m usage with 25m warn threshold must be ALLOW"
    );

    // 25 / 30 mins (1500s / 1800s) -> WARN
    assert_eq!(
        evaluate(1500, 1800, 1500, &active),
        PolicyDecision::Warn,
        "25m usage reaching warning threshold must be WARN"
    );

    // 29 / 30 mins (1740s / 1800s) -> WARN
    assert_eq!(
        evaluate(1740, 1800, 1500, &active),
        PolicyDecision::Warn,
        "Usage between warning and limit must be WARN"
    );

    // 30 / 30 mins (1800s / 1800s) -> LIMIT_REACHED
    assert_eq!(
        evaluate(1800, 1800, 1500, &active),
        PolicyDecision::LimitReached,
        "Exact limit must be LIMIT_REACHED"
    );

    // 31 / 30 mins (1860s / 1800s) -> ENFORCE
    assert_eq!(
        evaluate(1860, 1800, 1500, &active),
        PolicyDecision::Enforce,
        "Exceeded limit must be ENFORCE"
    );
}

#[test]
fn test_policy_engine_edge_cases() {
    let active = DeviceStatus::Active;
    let revoked = DeviceStatus::Revoked;

    // Zero daily limit means unconstrained access -> ALLOW
    assert_eq!(
        evaluate(10000, 0, 0, &active),
        PolicyDecision::Allow,
        "Zero daily limit must allow"
    );

    // Revoked device unconditionally evaluates to REVOKED
    assert_eq!(
        evaluate(10, 1800, 1500, &revoked),
        PolicyDecision::Revoked,
        "Revoked device state must produce REVOKED"
    );
}
