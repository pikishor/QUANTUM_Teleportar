extends RefCounted
## Static review of the CI / release workflows and the release scripts for secret leakage (no secrets are read or needed; the YAML is linted as text):
##   * no `pull_request_target`, a top-level `permissions:` block on every workflow and nothing writable in it
##   * no `${{ secrets.* }}` and no attacker-controlled expression (`github.event.*`, `head_ref`, `inputs.*`, `ref_name`) inside a `run:` script
##   * secrets reach scripts only through step `env:`, never through a job-level `env:`; no echo / printf / set -x of a secret variable (decoding into a file is fine);
##     nothing secret is written to GITHUB_ENV, so no later step (third-party actions included) inherits it
##   * a step that uses a secret is gated, so a repository without the secrets stays green; `actions/checkout` does not persist the token in a job that runs third-party actions
##   * the signing keystore is deleted at the end (`if: always()`); artifacts that can carry signed output or the signing identifiers are only kept for private repositories
##   * the release scripts never echo secret variables and clean up the temporary keychain and files on every exit
## The linter is checked against deliberately bad samples first, so a green result is not vacuous.
## Run: tools/test.sh tests/test_release_workflows.gd

const ECHO_RE := "^\\s*(echo|printf|cat)\\b"

## Identifiers the scripts treat as optional (empty = keep the preset's placeholder): a step that maps only these needs no gate (checked against export_ios.sh below).
const OPTIONAL_SECRETS: Array[String] = ["IOS_TEAM_ID", "IOS_BUNDLE_ID"]

var _secret_ref: RegEx
var _echo: RegEx
var _inject: RegEx
var _secret_only: RegEx


func _init() -> void:
	_echo = RegEx.create_from_string(ECHO_RE)
	_secret_ref = RegEx.create_from_string("secrets\\.([A-Za-z0-9_]+)")
	_inject = RegEx.create_from_string("\\$\\{\\{\\s*(github\\.event\\.|github\\.head_ref|inputs\\.|github\\.ref_name)")
	_secret_only = RegEx.create_from_string("^\\$\\{\\{\\s*secrets\\.[A-Za-z0-9_]+\\s*\\}\\}$")


# ---------------------------------------------------------------------------------------------------------------------
# a small YAML reader for the shape GitHub workflows have here (2-space indent, jobs -> steps list)
# ---------------------------------------------------------------------------------------------------------------------

static func _indent(l: String) -> int:
	var n := 0
	while n < l.length() and l[n] == " ":
		n += 1
	return n


static func _meaningful(l: String) -> bool:
	var t := l.strip_edges()
	return t != "" and not t.begins_with("#")


## "key: value" at the start of a (stripped) line, or ["", ""].
static func _kv(l: String) -> Array:
	var t := l.strip_edges()
	var i := t.find(":")
	if i <= 0 or t.begins_with("-") or t.begins_with("$") or t.begins_with("{") or t.begins_with("\"") or t.begins_with("echo"):
		return ["", ""]
	var k := t.substr(0, i)
	if " " in k:
		return ["", ""]
	var v := t.substr(i + 1)
	var c := v.find(" #")                                       # a trailing comment
	if c >= 0:
		v = v.substr(0, c)
	return [k, v.strip_edges()]


## Lines of the block under the key at line `i` (deeper than that line, blank lines kept).
static func _block(lines: PackedStringArray, i: int) -> PackedStringArray:
	var base := _indent(lines[i])
	var out := PackedStringArray()
	var j := i + 1
	while j < lines.size():
		if _meaningful(lines[j]) and _indent(lines[j]) <= base:
			break
		out.append(lines[j])
		j += 1
	return out


static func _map(block: PackedStringArray) -> Dictionary:
	var d := {}
	for l in block:
		if _meaningful(l):
			var kv := _kv(l)
			if kv[0] != "":
				d[kv[0]] = kv[1]
	return d


## {permissions: Array of lines or null, triggers: String, jobs: {name: {env: Dictionary, permissions: Array, steps: Array[Dictionary]}}}
static func parse(text: String) -> Dictionary:
	var lines := text.split("\n")
	var out := {"permissions": null, "triggers": "", "jobs": {}, "env": {}}
	var trig := PackedStringArray()
	for i in lines.size():
		var l := lines[i]
		if not _meaningful(l) or _indent(l) != 0:
			continue
		var kv := _kv(l)
		match kv[0]:
			"permissions":
				out["permissions"] = [l] + Array(_block(lines, i))
			"on":
				trig = _block(lines, i)
				trig.append(l)
			"env":
				out["env"] = _map(_block(lines, i))
			"jobs":
				var jl := _block(lines, i)
				out["jobs"] = _jobs(jl)
	out["triggers"] = "\n".join(trig)
	return out


static func _jobs(jl: PackedStringArray) -> Dictionary:
	var jobs := {}
	var i := 0
	while i < jl.size():
		var l := jl[i]
		if _meaningful(l) and _indent(l) == 2 and _kv(l)[0] != "":
			var name: String = _kv(l)[0]
			var body := _block(jl, i)
			jobs[name] = _job(body)
			i += 1 + body.size()
		else:
			i += 1
	return jobs


static func _job(body: PackedStringArray) -> Dictionary:
	var job := {"env": {}, "permissions": [], "steps": [], "raw": "\n".join(body)}
	for i in body.size():
		var l := body[i]
		if not _meaningful(l) or _indent(l) != 4:
			continue
		var kv := _kv(l)
		if kv[0] == "env":
			job["env"] = _map(_block(body, i))
		elif kv[0] == "permissions":
			job["permissions"] = [l] + Array(_block(body, i))
		elif kv[0] == "steps":
			job["steps"] = _steps(_block(body, i))
	return job


static func _steps(sl: PackedStringArray) -> Array:
	var items: Array[PackedStringArray] = []
	var cur := PackedStringArray()
	for l in sl:
		if _meaningful(l) and l.strip_edges().begins_with("- ") and _indent(l) == 6:
			if not cur.is_empty():
				items.append(cur)
			cur = PackedStringArray()
			cur.append(" ".repeat(8) + l.strip_edges().substr(2))     # the first key of the item joins the others at indent 8
		else:
			cur.append(l)
	if not cur.is_empty():
		items.append(cur)
	var out: Array = []
	for it in items:
		out.append(_step(it))
	return out


static func _step(it: PackedStringArray) -> Dictionary:
	var s := {"name": "", "id": "", "uses": "", "if": "", "run": "", "env": {}, "with": {}, "raw": "\n".join(it)}
	for i in it.size():
		var l := it[i]
		if not _meaningful(l) or _indent(l) != 8:
			continue
		var kv := _kv(l)
		match kv[0]:
			"name", "id", "uses", "if":
				s[kv[0]] = str(kv[1])
			"run":
				if str(kv[1]) in ["|", ">", "|-", ">-"]:
					s["run"] = "\n".join(_block(it, i))
				else:
					s["run"] = str(kv[1])
			"env":
				s["env"] = _map(_block(it, i))
			"with":
				s["with"] = _map(_block(it, i))
	return s


# ---------------------------------------------------------------------------------------------------------------------
# the rules: each returns the list of problems found in one parsed workflow
# ---------------------------------------------------------------------------------------------------------------------

func _secret_vars(wf: Dictionary, job: Dictionary, step: Dictionary) -> Array:
	var names: Array = []
	for d: Dictionary in [wf["env"], job["env"], step["env"]]:
		for k: String in d:
			if str(d[k]).contains("secrets."):
				names.append(k)
	return names


func _refs(line: String, name: String) -> bool:
	return line.contains("$" + name) or line.contains("${" + name)


func lint(text: String) -> PackedStringArray:
	var p := PackedStringArray()
	var wf := parse(text)
	for l in text.split("\n"):
		if _meaningful(l) and l.contains("pull_request_target"):
			p.append("pull_request_target is used")
	if wf["permissions"] == null:
		p.append("no top-level permissions block (the token gets the repository default)")
	else:
		for l: String in wf["permissions"]:
			if l.contains("write"):
				p.append("top-level permissions grant write: " + l.strip_edges())
	var jobs: Dictionary = wf["jobs"]
	for jn: String in jobs:
		var job: Dictionary = jobs[jn]
		for l: String in job["permissions"]:
			if l.contains("write"):
				p.append("job %s grants write: %s" % [jn, l.strip_edges()])
		for k: String in job["env"]:
			if _secret_only.search(str(job["env"][k]).strip_edges()) != null:
				p.append("job %s puts the secret %s in the job-level env (every step, third-party actions included, would see it)" % [jn, k])
		var third_party := false
		for s: Dictionary in job["steps"]:
			var u := str(s["uses"])
			if u != "" and not u.begins_with("actions/") and not u.begins_with("./"):
				third_party = true
		for s: Dictionary in job["steps"]:
			var label := "%s / %s" % [jn, str(s["name"]) if str(s["name"]) != "" else str(s["uses"])]
			var run := str(s["run"])
			if run.contains("secrets."):
				p.append("%s: ${{ secrets.* }} inside a run script (pass it through env:)" % label)
			if _inject.search(run) != null:
				p.append("%s: attacker-controlled expression inside a run script" % label)
			var names := _secret_vars(wf, job, s)
			var writes_env := run.contains("GITHUB_ENV") or run.contains("GITHUB_OUTPUT") or run.contains("GITHUB_STEP_SUMMARY")
			for l in run.split("\n"):
				var t := l.strip_edges()
				if t.begins_with("#"):
					continue
				if t == "set -x" or t.begins_with("set -x ") or t.contains("set -o xtrace") or t == "env" or t.begins_with("printenv"):
					p.append("%s: shell tracing / env dump (%s)" % [label, t])
				for n: String in names:
					if not _refs(t, n):
						continue
					var decode := t.contains("base64 --decode") or t.contains("base64 -d")
					if _echo.search(t) != null and not t.contains("::add-mask::") and not decode:
						p.append("%s: echoes the secret variable %s" % [label, n])
					elif writes_env and t.contains("=") and not t.begins_with("if ") and not t.begins_with("[") and not t.contains("::add-mask::") and not decode:
						p.append("%s: copies the secret variable %s towards GITHUB_ENV / OUTPUT" % [label, n])
			# gating: a step using a secret may only run when the gate says the secrets exist
			var raw := str(s["raw"])
			var needs_gate := false
			for m in _secret_ref.search_all(raw):
				if not OPTIONAL_SECRETS.has(m.get_string(1)):
					needs_gate = true
			if needs_gate and str(s["id"]) != "gate":
				var cond := str(s["if"])
				if not (cond.contains("signed == 'true'") or cond.contains("HAVE_")):
					p.append("%s: uses a secret without a gate (it would fail a repository that has none)" % label)
			if third_party and str(s["uses"]).begins_with("actions/checkout"):
				if str(s["with"].get("persist-credentials", "")) != "false":
					p.append("%s: checkout keeps the token in .git/config in a job that runs third-party actions" % label)
			if str(s["uses"]).begins_with("actions/upload-artifact"):
				var path := str(s["with"].get("path", "")) + str(s["raw"])
				var cond := str(s["if"])
				var carries_signed := path.contains(".aab") or path.contains("release.apk") or path.contains("/ipa")
				if carries_signed and not cond.contains("private == true"):
					p.append("%s: signed output is uploaded without the private-repository gate" % label)
				if path.contains("build/ios") and not path.contains("/ipa") and not (cond.contains("private == true") or cond.contains("HAVE_SIGNING != 'true'")):
					p.append("%s: the Xcode project (it carries the signing team / bundle id when secrets exist) is uploaded from a public repository" % label)
	# the keystore file is removed even when the build fails
	if text.contains("upload.keystore"):
		var cleaned := false
		for jn: String in jobs:
			for s: Dictionary in jobs[jn]["steps"]:
				if str(s["if"]).contains("always()") and str(s["run"]).contains("rm ") and str(s["run"]).contains("upload.keystore"):
					cleaned = true
		if not cleaned:
			p.append("the decoded keystore is never deleted (needs a step with if: always())")
	return p


## Script lint (tools/*.sh): no tracing, no echo of a secret variable except into base64 --decode, cleanup trap where a keychain or secret file is made.
func lint_script(text: String) -> PackedStringArray:
	var p := PackedStringArray()
	var sec := RegEx.create_from_string("\\$\\{?[A-Z0-9_]*(PASSWORD|KEYSTORE|_PW\\b|P12|PROVISION|PRIVATE_KEY|SERVICE_ACCOUNT|KCPW)[A-Z0-9_]*")
	for l in text.split("\n"):
		var t := l.strip_edges()
		if t.begins_with("#"):
			continue
		if t == "set -x" or t.begins_with("set -x ") or t.contains("set -o xtrace") or t.contains("bash -x"):
			p.append("shell tracing: " + t)
		if _echo.search(t) != null and sec.search(t) != null and not (t.contains("base64 --decode") or t.contains("base64 -d")):
			p.append("echoes a secret-looking variable: " + t)
	if text.contains("create-keychain") or text.contains("cert.p12"):
		var has_trap := false
		for l in text.split("\n"):
			if l.strip_edges().begins_with("trap ") and l.contains("delete-keychain") and l.contains("rm -rf"):
				has_trap = true
		if not has_trap:
			p.append("a keychain and a decoded certificate are created without a trap that deletes them on every exit")
	return p


# ---------------------------------------------------------------------------------------------------------------------

func _read(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	return f.get_as_text() if f != null else ""


func _has(p: PackedStringArray, needle: String) -> bool:
	for s in p:
		if s.contains(needle):
			return true
	return false


const BAD := """name: Bad
on:
  pull_request_target:
    types: [opened]
permissions:
  contents: write
jobs:
  release:
    runs-on: ubuntu-24.04
    env:
      TOKEN: ${{ secrets.DEPLOY_TOKEN }}
    steps:
      - uses: actions/checkout@v4
      - uses: some/third-party@v1
      - name: Leak
        env:
          PW: ${{ secrets.KEY_PASSWORD }}
        run: |
          set -x
          echo "password is $PW"
          LINE="PW=$PW"
          echo "$LINE" >> "$GITHUB_ENV"
          echo "${{ secrets.OTHER }}"
          echo "${{ github.event.pull_request.title }}"
      - uses: actions/upload-artifact@v4
        with:
          name: app
          path: build/app.aab
      - uses: actions/upload-artifact@v4
        with:
          name: xcode
          path: build/ios
"""

const GOOD := """name: Good
on:
  workflow_dispatch:
permissions:
  contents: read
jobs:
  release:
    runs-on: ubuntu-24.04
    steps:
      - name: Check signing secrets
        id: gate
        env:
          KS: ${{ secrets.KS }}
        run: |
          if [ -n "$KS" ]; then echo "signed=true" >> "$GITHUB_OUTPUT"; fi
      - uses: actions/checkout@v4
        if: steps.gate.outputs.signed == 'true'
        with:
          persist-credentials: false
      - name: Decode
        if: steps.gate.outputs.signed == 'true'
        env:
          KEYSTORE_B64: ${{ secrets.KS }}
        run: |
          echo "$KEYSTORE_B64" | base64 --decode > "$RUNNER_TEMP/upload.keystore"
      - uses: some/third-party@v1
        if: steps.gate.outputs.signed == 'true'
        with:
          key: ${{ secrets.KS }}
      - name: Remove the keystore
        if: always()
        run: rm -f "$RUNNER_TEMP/upload.keystore"
"""


func run(_host: Node) -> void:
	# the linter itself: it must flag every planted problem and stay quiet on a clean sample
	var bad := lint(BAD)
	TestLib.check(_has(bad, "pull_request_target"), "lint: flags pull_request_target")
	TestLib.check(_has(bad, "write"), "lint: flags a writable token")
	TestLib.check(_has(bad, "job-level env"), "lint: flags a secret in the job-level env")
	TestLib.check(_has(bad, "shell tracing"), "lint: flags set -x")
	TestLib.check(_has(bad, "echoes the secret variable PW"), "lint: flags an echoed secret")
	TestLib.check(_has(bad, "towards GITHUB_ENV"), "lint: flags a secret copied to GITHUB_ENV")
	TestLib.check(_has(bad, "inside a run script"), "lint: flags ${{ secrets }} in a script")
	TestLib.check(_has(bad, "attacker-controlled"), "lint: flags an injectable expression")
	TestLib.check(_has(bad, "without a gate"), "lint: flags an ungated secret use")
	TestLib.check(_has(bad, "keeps the token"), "lint: flags a persisted checkout token next to a third-party action")
	TestLib.check(_has(bad, "private-repository gate"), "lint: flags a signed artifact without the private gate")
	TestLib.check(_has(bad, "Xcode project"), "lint: flags the Xcode project artifact on a public repo")
	TestLib.check(_has(bad, "never deleted") or not BAD.contains("upload.keystore"), "lint: keystore rule only applies when a keystore is written")
	var good := lint(GOOD)
	TestLib.check(good.is_empty(), "lint: a clean workflow raises nothing (%s)" % "; ".join(good))
	var no_cleanup := lint(GOOD.replace("if: always()", "if: success()"))
	TestLib.check(_has(no_cleanup, "never deleted"), "lint: flags a keystore that is not removed with always()")
	TestLib.check(_has(lint_script("echo \"$IOS_CERT_PASSWORD\"\nset -x\n"), "echoes") and _has(lint_script("set -x\n"), "tracing"), "lint_script: flags echo of a password and set -x")
	TestLib.check(lint_script("echo \"$X\" | base64 --decode > f\n").is_empty(), "lint_script: decoding a secret into a file is fine")
	TestLib.check(_has(lint_script("security create-keychain -p x k\n"), "trap"), "lint_script: flags a keychain without cleanup")

	# the real files
	var root := ProjectSettings.globalize_path("res://").path_join("..").simplify_path()
	var dir := root.path_join(".github/workflows")
	var names: Array[String] = []
	var d := DirAccess.open(dir)
	if d != null:
		for f in d.get_files():
			if f.ends_with(".yml") or f.ends_with(".yaml"):
				names.append(f)
	names.sort()
	TestLib.check(names.has("android.yml") and names.has("ios.yml") and names.has("ci.yml"), "the three workflows are present (%s)" % ", ".join(names))
	for n in names:
		var text := _read(dir.path_join(n))
		var wf := parse(text)
		TestLib.check(wf["jobs"].size() >= 1, "%s: parsed %d job(s)" % [n, wf["jobs"].size()])
		var problems := lint(text)
		TestLib.check(problems.is_empty(), "%s: no secret-handling problems%s" % [n, "" if problems.is_empty() else " -> " + " | ".join(problems)])
	# the two signed paths are really inside the parsed workflows (so the rules above had something to bite on)
	var android := parse(_read(dir.path_join("android.yml")))
	TestLib.check(android["jobs"].has("release") and android["jobs"]["release"]["steps"].size() >= 10, "android.yml: the release job and its steps were parsed")
	var ios := parse(_read(dir.path_join("ios.yml")))
	TestLib.check(ios["jobs"].has("ios") and ios["jobs"]["ios"]["steps"].size() >= 8, "ios.yml: the ios job and its steps were parsed")
	TestLib.check(parse(_read(dir.path_join("ci.yml")))["permissions"] != null, "ci.yml: declares its permissions")

	# the identifiers that steps get without a gate really are optional for the script that reads them
	var exp_ios := _read(root.path_join("godot/tools/export_ios.sh"))
	TestLib.check(exp_ios.contains('[ -z "${IOS_TEAM_ID:-}" ]') and exp_ios.contains('[ -z "${IOS_BUNDLE_ID:-}" ]'), "export_ios.sh ignores an empty team / bundle id (the secrets may be absent)")

	# the scripts
	for rel in ["godot/tools/ios_build.sh", "godot/tools/export_android.sh", "godot/tools/export_ios.sh", "godot/tools/release/check_release_ready.sh", "godot/tools/bootstrap.sh", "godot/tools/soak.sh"]:
		var st := _read(root.path_join(rel))
		TestLib.check(st != "", "%s is readable" % rel)
		var sp := lint_script(st)
		TestLib.check(sp.is_empty(), "%s: no secret echo, no tracing, cleanup on exit%s" % [rel, "" if sp.is_empty() else " -> " + " | ".join(sp)])
