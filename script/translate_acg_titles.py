"""Run on the NAS: translate public RSS titles through its loopback Ollama API."""

import fcntl
import json
import os
import pathlib
import re
import subprocess
import sys
import tempfile
import urllib.request

MODEL = "hf.co/tencent/HY-MT1.5-1.8B-GGUF:Q4_K_M"
STATE = pathlib.Path("/vol1/docker/discourse-preview/shared/state")
CACHE = STATE / "acg-daily-translations.json"


def validate_translation(title, translated):
    if not isinstance(translated, str):
        raise ValueError("Translation must be text")
    translated = translated.strip()
    if not translated or len(translated) > 500 or "\n" in translated:
        raise ValueError("Expected a single translated title")
    if not re.search(r"[\u4e00-\u9fff]", translated):
        raise ValueError("Translation contains no Chinese text")
    numbers = lambda text: re.findall(r"\d[\d,]*(?:\.\d+)?", text.replace(",", ""))
    numeric_title = re.sub(r"\b\d+(?:st|nd|rd|th)\b", "", title, flags=re.I)
    if not set(numbers(numeric_title)).issubset(numbers(translated)):
        raise ValueError("Translation changed or omitted numbers")
    return translated


def translate(title):
    prompt = (
        "<｜hy_begin▁of▁sentence｜><｜hy_User｜>"
        "将以下资讯标题的新闻叙述翻译成简体中文。作品名、人名和平台名保留英文原拼写，不要音译。数字保留阿拉伯数字。只输出一行译文，不要解释：\n\n"
        + title
        + "<｜hy_Assistant｜>"
    )
    payload = {
        "model": MODEL,
        "prompt": prompt,
        "raw": True,
        "stream": False,
        "keep_alive": "2m",
        "options": {"num_gpu": 0, "num_ctx": 1024, "num_predict": 160, "temperature": 0},
    }
    request = urllib.request.Request(
        "http://127.0.0.1:11434/api/generate",
        data=json.dumps(payload).encode(),
        headers={"Content-Type": "application/json"},
    )
    with urllib.request.urlopen(request, timeout=90) as response:
        result = json.load(response)
    if result.get("error") or result.get("done_reason") != "stop":
        raise ValueError("Translation did not complete normally")
    return validate_translation(title, result.get("response"))


def save_cache(cache):
    with tempfile.NamedTemporaryFile(mode="w", dir=STATE, delete=False, encoding="utf-8") as output:
        json.dump(cache, output, ensure_ascii=False)
        temporary = output.name
    try:
        os.replace(temporary, CACHE)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def rails(option):
    return subprocess.check_output(
        ["docker", "--context", "default", "exec", "-u", "discourse", "app", "bash", "-lc",
         "cd /var/www/discourse && bin/rails runner /shared/state/acg_daily_bot.rb " + option],
        text=True,
        timeout=180,
    )


def main():
    with (STATE / "acg-daily-translation.lock").open("a") as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            print(json.dumps({"status": "translation_job_running"}))
            return
        prepared = json.loads(rails("--prepare-translations").strip().splitlines()[-1])
        if prepared["status"] == "already_published":
            print(json.dumps(prepared))
            return
        cache = json.loads(CACHE.read_text()) if CACHE.exists() else {}
        translated = 0
        failed = 0
        for title in prepared["titles"]:
            if title in cache:
                continue
            try:
                cache[title] = translate(title)
                save_cache(cache)
                translated += 1
            except Exception as error:
                # Translation failure must not prevent publishing the source title.
                failed += 1
                print(json.dumps({"status": "translation_failed", "error": str(error)}), flush=True)
        print(json.dumps({"status": "translations_ready", "translated": translated, "failed": failed}), flush=True)
        print(rails("--publish").strip())


if __name__ == "__main__":
    if "--self-test" in sys.argv:
        assert validate_translation("Anime debuts in 2027", "动画于2027年开播") == "动画于2027年开播"
        for invalid in ["English only 2027", "动画于2028年开播", "解释\n动画于2027年开播", None]:
            try:
                validate_translation("Anime debuts in 2027", invalid)
            except ValueError:
                continue
            raise AssertionError("Invalid translation accepted")
        assert validate_translation("5,000 sales", "销量5000份") == "销量5000份"
        assert validate_translation("2nd part in April 2027", "第二部分于2027年4月开播")
        import contextlib
        import io

        with tempfile.TemporaryDirectory() as directory:
            STATE = pathlib.Path(directory)
            CACHE = STATE / "cache.json"
            calls = []

            def rails(option):
                calls.append(option)
                return json.dumps({"status": "translation_titles", "titles": ["Anime 2027", "Failed title"]}) if option == "--prepare-translations" else '{"status":"published"}'

            def translate(title):
                if title == "Failed title":
                    raise TimeoutError("Sample timeout")
                return "动画2027"

            with contextlib.redirect_stdout(io.StringIO()):
                main()
            assert calls == ["--prepare-translations", "--publish"]
            assert json.loads(CACHE.read_text()) == {"Anime 2027": "动画2027"}
        print("Translation self-check passed")
    else:
        main()
