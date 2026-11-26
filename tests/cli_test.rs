// SPDX-License-Identifier: Apache-2.0

use std::process::Command;

fn run(repository: &str, dir: &std::path::Path) -> (bool, String) {
    let input = dir.join("bill.json");
    let out = dir.join("out.json");
    let item = |repo: &str| {
        format!(
            r#"{{"date":"2025-01-01","product":"actions","sku":"actions_linux","quantity":10.0,
            "unitType":"minutes","pricePerUnit":0.008,"grossAmount":0.08,"discountAmount":0.08,
            "netAmount":0.0,"organizationName":"DigitalPebble","repositoryName":"{repo}"}}"#
        )
    };
    std::fs::write(
        &input,
        format!(
            r#"{{"usageItems":[{},{}]}}"#,
            item("public-repo"),
            item("secret-repo")
        ),
    )
    .unwrap();

    let status = Command::new(env!("CARGO_BIN_EXE_aspen"))
        .args([
            "--file",
            input.to_str().unwrap(),
            "-O",
            out.to_str().unwrap(),
        ])
        .args(["--repository", repository])
        .env_remove("INPUT_REPOSITORY")
        .env_remove("GITHUB_STEP_SUMMARY")
        .env_remove("GITHUB_OUTPUT")
        .status()
        .unwrap();
    let report = std::fs::read_to_string(&out).unwrap_or_default();
    (status.success(), report)
}

#[test]
fn report_only_contains_the_selected_repository() {
    let dir = std::env::temp_dir().join(format!("aspen-cli-{}", std::process::id()));
    std::fs::create_dir_all(&dir).unwrap();
    let (ok, report) = run("DigitalPebble/public-repo", &dir);
    assert!(ok);
    assert!(report.contains("public-repo"));
    assert!(!report.contains("secret-repo"));
    std::fs::remove_dir_all(&dir).ok();
}

#[test]
fn invalid_repository_fails() {
    let dir = std::env::temp_dir().join(format!("aspen-cli-bad-{}", std::process::id()));
    std::fs::create_dir_all(&dir).unwrap();
    let (ok, report) = run("not-a-repo", &dir);
    assert!(!ok);
    assert!(report.is_empty());
    std::fs::remove_dir_all(&dir).ok();
}

#[test]
fn badge_is_written_when_requested() {
    let dir = std::env::temp_dir().join(format!("aspen-cli-badge-{}", std::process::id()));
    std::fs::create_dir_all(&dir).unwrap();
    let badge = dir.join("sub").join("badge.json");
    let input = dir.join("bill.json");
    std::fs::write(&input, r#"{"usageItems":[]}"#).unwrap();

    let status = Command::new(env!("CARGO_BIN_EXE_aspen"))
        .args(["--file", input.to_str().unwrap()])
        .args(["-O", dir.join("out.json").to_str().unwrap()])
        .args(["--badge", badge.to_str().unwrap()])
        .env_remove("GITHUB_STEP_SUMMARY")
        .env_remove("GITHUB_OUTPUT")
        .status()
        .unwrap();
    assert!(status.success());

    let v: serde_json::Value =
        serde_json::from_str(&std::fs::read_to_string(&badge).unwrap()).unwrap();
    assert_eq!(v["schemaVersion"], 1);
    assert_eq!(v["message"], "0.0 gCO2e");
    assert_eq!(v["color"], "ffd700"); // data read from a file is billing data: gold
    std::fs::remove_dir_all(&dir).ok();
}

#[test]
fn filter_mode_accepts_a_personal_account_export() {
    use std::io::Write;
    use std::process::Stdio;

    let input = r#"{"usageItems":[{"date":"2026-04-01T00:00:00Z","product":"actions",
        "sku":"Actions Linux","quantity":1.0,"unitType":"Minutes","pricePerUnit":0.006,
        "grossAmount":0.006,"discountAmount":0.006,"netAmount":0.0,"repositoryName":"aspen"}]}"#;
    let mut child = Command::new(env!("CARGO_BIN_EXE_aspen"))
        .env_remove("INPUT_GITHUB_TOKEN")
        .env_remove("INPUT_ORGANIZATION")
        .env_remove("INPUT_REPOSITORY")
        .env_remove("GITHUB_STEP_SUMMARY")
        .env_remove("GITHUB_OUTPUT")
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .unwrap();
    child
        .stdin
        .take()
        .unwrap()
        .write_all(input.as_bytes())
        .unwrap();
    let out = child.wait_with_output().unwrap();
    assert!(
        out.status.success(),
        "{}",
        String::from_utf8_lossy(&out.stderr)
    );
    let stdout = String::from_utf8(out.stdout).unwrap();
    assert!(stdout.contains(r#""repositoryName": "aspen""#));
    assert!(!stdout.contains("organizationName"));
}
