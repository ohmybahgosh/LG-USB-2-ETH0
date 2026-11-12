#!/usr/bin/env python3
"""Special thanks: everyone who has helped build LG-USB-2-ETH0 on GitHub, kept up to
date in README.md (between <!-- thanks:start --> and <!-- thanks:end -->) and in
assets/thanks.json, which ohmybahgosh.dev reads for the project page.

    python3 scripts/gen-thanks.py            write both files
    python3 scripts/gen-thanks.py --check    exit 1 if they are out of date

Counts merged pull requests, driver tests, compatibility reports, other issues
(bugs and ideas) and discussions, from everyone but the owner and bots.
GITHUB_TOKEN is needed for discussions (GitHub's GraphQL API) and raises the rate
limit; REPO overrides the repository.  The Thanks workflow runs it when a pull
request is merged or an issue or discussion is opened, and every day.
Standard library only.
"""
import json, os, sys, urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
REPO = os.environ.get("REPO", "ohmybahgosh/LG-USB-2-ETH0")
OWNER = REPO.split("/")[0].lower()
TOKEN = os.environ.get("GITHUB_TOKEN") or os.environ.get("GH_TOKEN")
START, END = "<!-- thanks:start -->", "<!-- thanks:end -->"
EMPTY = "Nobody yet.  Test a driver, send a compatibility report, or open a pull request, and your name goes here."
# what each kind is called, one and many, in the order they're listed
KINDS = [
    ("prs", "pull request", "pull requests"),
    ("tests", "driver test", "driver tests"),
    ("compat", "compatibility report", "compatibility reports"),
    ("issues", "bug report or idea", "bug reports and ideas"),
    ("talks", "discussion", "discussions"),
]


def api(url, body=None):
    h = {"Accept": "application/vnd.github+json", "User-Agent": "lg-usb-2-eth0-thanks"}
    if TOKEN:
        h["Authorization"] = "Bearer " + TOKEN
    data = json.dumps(body).encode() if body is not None else None
    with urllib.request.urlopen(urllib.request.Request(url, data=data, headers=h), timeout=30) as r:
        return json.load(r)


def skip(user):
    login = (user or {}).get("login") or ""
    return not login or login.lower() == OWNER or (user or {}).get("type") == "Bot" or login.endswith("[bot]")


def people():
    by = {}
    def add(user, kind):
        p = by.setdefault(user["login"], {"login": user["login"], "url": user.get("html_url") or "https://github.com/" + user["login"],
                                          "avatar": user.get("avatar_url") or "https://github.com/%s.png" % user["login"], **{k: 0 for k, _, _ in KINDS}})
        p[kind] += 1
    for page in range(1, 50):
        items = api("https://api.github.com/repos/%s/issues?state=all&per_page=100&page=%d" % (REPO, page))
        for it in items:
            if skip(it.get("user")):
                continue
            labels = {l["name"].lower() for l in it.get("labels") or []}
            if "pull_request" in it:
                if it["pull_request"].get("merged_at"):
                    add(it["user"], "prs")
            elif labels & {"invalid", "spam"}:
                continue
            elif "driver-test" in labels:
                add(it["user"], "tests")
            elif "compatibility" in labels:
                add(it["user"], "compat")
            else:
                add(it["user"], "issues")
        if len(items) < 100:
            break
    if TOKEN:
        owner, name = REPO.split("/")
        after = None
        while True:
            q = "query($o:String!,$n:String!,$a:String){repository(owner:$o,name:$n){discussions(first:100,after:$a){pageInfo{hasNextPage endCursor} nodes{author{login url avatarUrl __typename}}}}}"
            d = api("https://api.github.com/graphql", {"query": q, "variables": {"o": owner, "n": name, "a": after}})["data"]["repository"]["discussions"]
            for n in d["nodes"]:
                a = n.get("author") or {}
                u = {"login": a.get("login"), "html_url": a.get("url"), "avatar_url": a.get("avatarUrl"), "type": "Bot" if a.get("__typename") == "Bot" else "User"}
                if not skip(u):
                    add(u, "talks")
            if not d["pageInfo"]["hasNextPage"]:
                break
            after = d["pageInfo"]["endCursor"]
    else:
        print("No GITHUB_TOKEN, so discussions aren't counted", file=sys.stderr)
    score = lambda p: (-p["prs"], -p["tests"], -(p["compat"] + p["issues"] + p["talks"]), p["login"].lower())
    return sorted(by.values(), key=score)


def what(p):
    return ", ".join("%d %s" % (p[k], one if p[k] == 1 else many) for k, one, many in KINDS if p[k])


def esc(s):
    return str(s).replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;").replace('"', "&quot;")


def avatar(p, size):
    return p["avatar"] + ("&" if "?" in p["avatar"] else "?") + "s=%d" % (size * 2)


def readme(ps):
    if not ps:
        return EMPTY
    imgs = "\n".join('  <a href="%s" title="%s"><img src="%s" width="48" height="48" alt="%s"></a>' % (esc(p["url"]), esc(p["login"] + ": " + what(p)), esc(avatar(p, 48)), esc(p["login"])) for p in ps)
    return "<p>\n%s\n</p>\n\n%s" % (imgs, "\n".join("- **[%s](%s)**: %s" % (p["login"], p["url"], what(p)) for p in ps))


def main():
    ps = people()
    f = os.path.join(ROOT, "README.md")
    s = open(f, encoding="utf-8").read()
    a, b = s.find(START), s.find(END)
    if a < 0 or b < a:
        sys.exit("README.md has no %s ... %s block" % (START, END))
    new_readme = s[:a + len(START)] + "\n" + readme(ps) + "\n" + s[b:]
    j = os.path.join(ROOT, "assets", "thanks.json")
    new_json = json.dumps({"repo": REPO, "people": [{"login": p["login"], "url": p["url"], "avatar": p["avatar"], "what": what(p)} for p in ps]}, indent=1) + "\n"
    old_json = open(j, encoding="utf-8").read() if os.path.exists(j) else ""
    stale = [x for x, new, old in (("README.md", new_readme, s), ("assets/thanks.json", new_json, old_json)) if new != old]
    if "--check" in sys.argv:
        if stale:
            sys.exit("Out of date: " + ", ".join(stale))
        print("Special thanks is up to date (%d people)" % len(ps))
        return
    if new_readme != s:
        open(f, "w", encoding="utf-8").write(new_readme)
    if new_json != old_json:
        open(j, "w", encoding="utf-8").write(new_json)
    print("%d people: %s%s" % (len(ps), "; ".join("%s (%s)" % (p["login"], what(p)) for p in ps), "" if stale else "  (no change)"))


if __name__ == "__main__":
    main()
