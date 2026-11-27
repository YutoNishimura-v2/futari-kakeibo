"""Export only named Futari screenshots from the Xcode attachment manifest."""

import json
import os
import shutil
from pathlib import Path

SCREENS = {
    "home": "ホーム",
    "entry": "支出入力",
    "monthly-detail": "月の明細",
    "settlement": "月の精算",
    "budgets": "費目別予算",
    "paywall": "購入画面",
}
STYLES = {"light": "ライト", "dark": "ダーク"}
PNG_SIGNATURE = b"\x89PNG\r\n\x1a\n"


def main() -> None:
    """Require one PNG per screen and appearance, then write the gallery."""
    attachments = Path("tmp/attachments")
    output = Path("tmp/ci-shots")
    manifest = json.loads((attachments / "manifest.json").read_text(encoding="utf-8"))
    shots = {}
    for test in manifest:
        for entry in test["attachments"]:
            name = entry["suggestedHumanReadableName"]
            for screen in SCREENS:
                for style in STYLES:
                    stem = f"{screen}-{style}"
                    if name not in (stem, f"{stem}.png") and not name.startswith(f"{stem}_"):
                        continue
                    file = attachments / Path(entry["exportedFileName"]).name
                    with file.open("rb") as stream:
                        if stream.read(len(PNG_SIGNATURE)) != PNG_SIGNATURE:
                            raise SystemExit(f"Invalid PNG attachment: {name}")
                    if stem in shots:
                        raise SystemExit(f"Duplicate attachment: {stem}")
                    shots[stem] = file

    expected = {f"{screen}-{style}" for screen in SCREENS for style in STYLES}
    if missing := expected - shots.keys():
        raise SystemExit(f"Missing screenshots: {', '.join(sorted(missing))}")
    output.mkdir()
    run_url = (
        f"{os.environ['GITHUB_SERVER_URL']}/{os.environ['GITHUB_REPOSITORY']}"
        f"/actions/runs/{os.environ['GITHUB_RUN_ID']}"
    )
    index = [
        f"成功 {os.environ['GITHUB_SHA']}",
        "",
        f"実行: {run_url}",
        "",
        "# ふたりの家計簿",
        "",
    ]
    for style, appearance in STYLES.items():
        index.extend([f"## {appearance}", ""])
        for screen, title in SCREENS.items():
            stem = f"{screen}-{style}"
            filename = f"{stem}.png"
            shutil.copyfile(shots[stem], output / filename)
            index.extend([f"### {title}", "", f"![{title}（{appearance}）]({filename})", ""])
    (output / "index.md").write_text("\n".join(index), encoding="utf-8")


if __name__ == "__main__":
    main()
