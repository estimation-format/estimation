*! version 0.1.0  estrec: Stata estimation results as estimation records
*
* estrec write using FILE [, replace level(#) noidentifying nodatasignature call() noestat]
*
* Run it right after an estimation command. It reads e() and writes one record (JSON)
* claiming the profiles the command fits:
*
*   regress                         inference/0.1
*   areg, xtreg fe, reghdfe         inference/0.1, linear-fe/0.1
*   xtreg re                        inference/0.1
*   ivregress, ivreg2               inference/0.1, iv/0.1
*   ivreghdfe                       inference/0.1, iv/0.1, linear-fe/0.1
*   logit, logistic, probit,        glm/0.1
*     poisson, nbreg
*   glm                             inference/0.1, glm/0.1 (glm, irls: inference/0.1 only)
*
* Any other e-class command with e(b) and e(V) gets a core record with no profile claims.
* Results from prefixes (svy:, mi estimate:, bootstrap:, ...) aren't supported yet.
*
* Options:
*   replace          overwrite the file
*   level(#)         disclosure level, 1-5 (spec 4.9; default 4)
*   noidentifying    leave out user, host and the data file's path (level 5 only)
*   nodatasignature  skip the in-memory data checksum (datasignature)
*   call(string)     the command as written (default: e(cmdline))
*   noestat          after ivregress, don't run estat firststage/overid/endogenous
*
* The record has no core digest (meta.core_digest is optional): computing it needs RFC 8785
* canonical JSON. Add it with the reference tool: `estimation digest --write FILE`.

program define estrec
	version 16
	gettoken sub 0 : 0, parse(" ,")
	if `"`sub'"' == "write" {
		_estrec_write `0'
	}
	else if `"`sub'"' == "" | `"`sub'"' == "version" {
		di as txt "estrec 0.1.0"
	}
	else {
		di as err `"estrec: unknown subcommand {bf:`sub'}; use {bf:estrec write using} {it:file}"'
		exit 199
	}
end

program define _estrec_write
	version 16
	syntax using/ [, REPLACE noIDENTifying noDATASIGnature CALL(string asis) LEVel(integer 4) noESTat]
	if `level' < 1 | `level' > 5 {
		di as err "estrec write: level() must be 1 to 5"
		exit 198
	}
	if "`e(cmd)'" == "" {
		di as err "estrec write: no estimation results; run an estimation command first"
		exit 301
	}
	if "`e(prefix)'" != "" {
		di as err "estrec write: results from the `e(prefix)' prefix aren't supported yet"
		exit 198
	}
	capture confirm matrix e(b)
	local rc = _rc
	capture confirm matrix e(V)
	if `rc' | _rc {
		di as err "estrec write: `e(cmd)' posted no e(b) and e(V)"
		exit 301
	}
	if `"`call'"' == "" local call `"`e(cmdline)'"'

	* Which mapping applies
	local cmd `e(cmd)'
	if "`cmd'" == "regress" local kind regress
	else if "`cmd'" == "areg" local kind areg
	else if "`cmd'" == "xtreg" & inlist("`e(model)'", "fe", "re") local kind xtreg_`e(model)'
	else if "`cmd'" == "reghdfe" & "`e(model)'" == "ols" local kind reghdfe
	else if "`cmd'" == "ivregress" local kind ivregress
	else if inlist("`cmd'", "ivreg2", "ivreghdfe") local kind `cmd'
	else if inlist("`cmd'", "logit", "logistic", "probit", "poisson", "nbreg") local kind ml
	else if "`cmd'" == "glm" local kind glm
	else local kind generic

	* The data as the user has it, before any temporary variable is added
	local nvars = c(k)
	local rows_input = c(N)
	if "`datasignature'" == "" {
		quietly datasignature
		local datasig "`r(datasignature)'"
	}

	* Rows dropped for missing values: the model's variables, marked out over the whole data
	local names `e(depvar)' `e(absvars)' `e(absvar)' `e(clustvar)' `e(ivar)' `e(instd)' `e(insts)' `e(exog)' `e(endog)'
	local cols : colnames e(b)
	local cols = subinstr(`"`cols'"', "#", " ", .)
	foreach t of local cols {
		local names `names' `=ustrregexra("`t'", "^.*\.", "")'
	}
	local wvar = trim(subinstr("`e(wexp)'", "=", "", 1))
	local ovar = ustrregexra("`e(offset)'", "^ln\((.*)\)$", "$1")
	local names `names' `wvar' `ovar'
	local vars
	foreach t of local names {
		capture confirm variable `t', exact
		if !_rc local vars `vars' `t'
	}
	local vars : list uniq vars
	tempvar touse
	quietly generate byte `touse' = 1
	if "`vars'" != "" markout `touse' `vars', strok
	quietly count if `touse'
	local n_complete = r(N)
	drop `touse'
	capture quietly count if e(sample)
	local n_used = cond(_rc | r(N) == 0, ., r(N))

	* Versions from the first line of each package's ado file
	foreach p in `cmd' ftools ranktest ivreg2 {
		local ver_`p'
		capture findfile `p'.ado
		if !_rc {
			tempname fh
			file open `fh' using `"`r(fn)'"', read text
			file read `fh' line
			file close `fh'
			if ustrregexm(`"`line'"', "([0-9]+\.[0-9]+(\.[0-9]+)*)") local ver_`p' = ustrregexs(1)
		}
	}
	local ver_cmd `ver_`cmd''

	* UTC time from the OS (Stata has none)
	tempfile clock
	if c(os) == "Windows" {
		quietly shell powershell -NoProfile -Command "[DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ')" > "`clock'"
	}
	else {
		quietly shell date -u +%Y-%m-%dT%H:%M:%SZ > "`clock'"
	}
	local created
	capture {
		tempname fh
		file open `fh' using "`clock'", read text
		file read `fh' created
		file close `fh'
	}
	local created = trim(`"`created'"')
	if !ustrregexm(`"`created'"', "^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$") {
		di as err "estrec write: couldn't read the UTC time from the operating system"
		exit 198
	}

	local doestat = "`estat'" == ""
	local ident = "`identifying'" == ""
	local tis : char _dta[tis]
	local iis : char _dta[iis]
	mata: _er_write(`"`using'"', "`replace'" != "", `level')
	di as txt `"estimation record written to {browse "`using'"}"'
end


version 16
mata:
mata set matastrict on

// ---- JSON --------------------------------------------------------------------------

string scalar _ej_s(string scalar s)
{
	string scalar r
	real scalar i
	r = subinstr(s, "\", "\\")
	r = subinstr(r, `"""', `"\""')
	r = subinstr(r, char(10), "\n")
	r = subinstr(r, char(13), "\r")
	r = subinstr(r, char(9), "\t")
	for (i = 1; i < 32; i++) {
		if (i != 9 & i != 10 & i != 13) r = subinstr(r, char(i), "\u00" + (i < 16 ? "0" : "") + inbase(16, i))
	}
	return(`"""' + r + `"""')
}

// JSON number; Stata missing -> null. 17 significant digits round-trip a double
string scalar _ej_n(real scalar x)
{
	string scalar r
	if (missing(x)) return("null")
	if (x == trunc(x) & abs(x) < 1e15) return(strtrim(sprintf("%20.0f", x)))
	r = strtrim(sprintf("%24.17g", x))
	if (substr(r, 1, 1) == ".") r = "0" + r
	if (substr(r, 1, 2) == "-.") r = "-0" + substr(r, 2, .)
	return(r)
}

// A number, or "" (left out) when missing
string scalar _ej_nx(real scalar x)
{
	return(missing(x) ? "" : _ej_n(x))
}

string scalar _ej_b(real scalar x)
{
	return(x ? "true" : "false")
}

string scalar _ej_sa(string vector v)
{
	string scalar r
	real scalar i
	r = "["
	for (i = 1; i <= length(v); i++) r = r + (i > 1 ? ", " : "") + _ej_s(v[i])
	return(r + "]")
}

string scalar _ej_na(real vector v)
{
	string scalar r
	real scalar i
	r = "["
	for (i = 1; i <= length(v); i++) r = r + (i > 1 ? ", " : "") + _ej_n(v[i])
	return(r + "]")
}

// [a, b, ...] of already-encoded values; "" when empty
string scalar _ej_l(string vector v)
{
	return(length(v) ? "[" + invtokens(v, ", ") + "]" : "")
}

// {"k": v, ...}; entries whose value is "" are left out
string scalar _ej_o(string vector k, string vector v)
{
	string scalar r
	real scalar i, n
	r = "{"
	n = 0
	for (i = 1; i <= length(k); i++) {
		if (v[i] == "") continue
		r = r + (n++ ? ", " : "") + _ej_s(k[i]) + ": " + v[i]
	}
	return(r + "}")
}

// {value, definition}
string scalar _ej_def(string scalar v, string scalar definition)
{
	if (v == "" | definition == "") return(v)
	return(_ej_o(("value", "definition"), (v, _ej_s(definition))))
}

// An object built field by field, each field with its disclosure level (spec 4.9)
struct erobj {
	string rowvector k, v
	real rowvector l
}

struct erobj scalar _on()
{
	struct erobj scalar o
	o.k = J(1, 0, "")
	o.v = J(1, 0, "")
	o.l = J(1, 0, .)
	return(o)
}

void _oa(struct erobj scalar o, string scalar key, string scalar val, real scalar lvl)
{
	if (val == "") return
	o.k = o.k, key
	o.v = o.v, val
	o.l = o.l, lvl
}

// The fields at or below level lv; "" when none is left
string scalar _or(struct erobj scalar o, real scalar lv)
{
	string scalar r
	real scalar i, n
	r = "{"
	n = 0
	for (i = 1; i <= length(o.k); i++) {
		if (o.l[i] > lv) continue
		r = r + (n++ ? ", " : "") + _ej_s(o.k[i]) + ": " + o.v[i]
	}
	return(n ? r + "}" : "")
}

// ---- e() ---------------------------------------------------------------------------

// A scalar, or missing when it isn't set (st_numscalar returns 0 x 0 then)
real scalar _sc(string scalar name)
{
	real matrix x
	x = st_numscalar(name)
	return(rows(x) ? x : .)
}

real scalar _e(string scalar name)
{
	return(_sc("e(" + name + ")"))
}

string scalar _en(string scalar name)
{
	return(_ej_nx(_e(name)))
}

string scalar _eg(string scalar name)
{
	return(st_global("e(" + name + ")"))
}

real scalar _isin(string scalar s, string vector set)
{
	return(anyof(set, s))
}

// One Stata column name -> canonical JSON and the dropped reason ("" when kept)
void _er_term(string scalar term, string scalar canon, string scalar dropped)
{
	string vector parts
	string rowvector factors
	string scalar p, var, level, flags, name
	real scalar i, nlev, ncont

	dropped = ""
	if (term == "_cons") {
		canon = `"{"name": "(Intercept)", "factors": []}"'
		return
	}
	parts = tokens(term, "#")
	parts = select(parts, parts :!= "#")
	factors = J(1, 0, "")
	name = ""
	nlev = ncont = 0
	for (i = 1; i <= length(parts); i++) {
		p = parts[i]
		if (regexm(p, "^([0-9]+)([a-z]*)\.(.+)$")) {
			level = regexs(1); flags = regexs(2); var = regexs(3)
			if (strpos(flags, "b")) dropped = "reference"
			if (strpos(flags, "o")) dropped = "collinear"
			factors = factors, _ej_o(("variable", "level"), (_ej_s(var), _ej_s(level)))
			name = name + (i > 1 ? "#" : "") + level + "." + var
			nlev++
		}
		else {
			if (regexm(p, "^([a-z]*)\.(.+)$")) {
				flags = regexs(1); var = regexs(2)
				if (strpos(flags, "o")) dropped = "collinear"
			}
			else var = p
			factors = factors, _ej_o("variable", _ej_s(var))
			name = name + (i > 1 ? "#" : "") + "c." + var
			ncont++
		}
	}
	// R form except factor x continuous, which keeps Stata's form (spec 4.4.1)
	if (!(nlev & ncont)) {
		name = ""
		for (i = 1; i <= length(parts); i++) {
			p = parts[i]
			if (regexm(p, "^([0-9]+)[a-z]*\.(.+)$")) name = name + (i > 1 ? ":" : "") + regexs(2) + regexs(1)
			else if (regexm(p, "^[a-z]*\.(.+)$")) name = name + (i > 1 ? ":" : "") + regexs(1)
			else name = name + (i > 1 ? ":" : "") + p
		}
	}
	canon = _ej_o(("name", "factors"), (_ej_s(name), "[" + invtokens(factors, ", ") + "]"))
}

// ---- tests -------------------------------------------------------------------------

struct ertests {
	string rowvector t
	real scalar n
}

// One test: name, category, statistic, distribution ("F", "chi2" or ""), df1, df2, p
void _ta(struct ertests scalar T, string scalar category, string scalar name, real scalar stat,
	string scalar dist, real scalar df1, real scalar df2, real scalar p, string scalar origin,
	string scalar response, string scalar label, string scalar source)
{
	string rowvector k, v
	if (missing(stat) & missing(p)) return
	T.n = T.n + 1
	k = ("id", "category", "name", "origin", "response", "label", "statistic", "distribution")
	v = (_ej_s("t" + strofreal(T.n)), _ej_s(category), _ej_s(name), _ej_s(origin),
		(response != "" ? _ej_s(response) : ""), (label != "" ? _ej_s(label) : ""),
		_ej_nx(stat), (dist != "" & !missing(stat) ? _ej_s(dist) : ""))
	if (dist == "F") {
		k = k, ("df1", "df2")
		v = v, (_ej_nx(df1), _ej_nx(df2))
	}
	else if (dist == "chi2") {
		k = k, "df"
		v = v, _ej_nx(df1)
	}
	k = k, ("p_value", "source")
	v = v, (_ej_nx(p), source)
	T.t = T.t, _ej_o(k, v)
}

// ---- the record --------------------------------------------------------------------

void _er_write(string scalar fn, real scalar replace, real scalar lv)
{
	string scalar cmd, kind, wver, vce, vtype, wtype, wvar, conv, formula, kcounts, dfdef
	string scalar canon, dropped, term, eq, eq1, created, nl, rec, depvar, s, ver_cmd, src
	string matrix cs, rs
	string rowvector clusters, absvars, params, vrows, fe, software, sections, endog, insts, exogr
	string rowvector profiles, messages, perendog, rn, cn, fcn, vcovs, histk, histv
	real matrix b, V, dof, M, Vm
	real scalar N, nobs, dfr, dft, small, linear, ml, iv, ncl, i, j, k, se, t, crit, level, lvconf
	real scalar nsing, rows_input, n_complete, n_used, n_missing, n_other, conv_ok, fh, ident, rank
	real scalar doestat, dev, alpha, rc, isiid, haveabs, fw
	struct erobj scalar meta, metrics, spec, sample, structures, prov, est, vc, opts, num, vm
	struct ertests scalar T

	cmd = _eg("cmd")
	kind = st_local("kind")
	wver = "0.1.0"
	ver_cmd = st_local("ver_cmd")
	ident = strtoreal(st_local("ident"))
	doestat = strtoreal(st_local("doestat"))
	created = st_local("created")
	rows_input = strtoreal(st_local("rows_input"))
	n_complete = strtoreal(st_local("n_complete"))
	n_used = strtoreal(st_local("n_used"))
	depvar = _eg("depvar")

	b = st_matrix("e(b)")
	V = st_matrix("e(V)")
	cs = st_matrixcolstripe("e(b)")
	N = _e("N")
	dfr = _e("df_r")
	rank = _e("rank")
	if (missing(rank)) rank = sum(diagonal(st_matrix("e(V)")) :!= 0)
	level = c("level")
	wtype = _eg("wtype")
	wvar = strtrim(subinstr(_eg("wexp"), "=", "", 1))
	fw = wtype == "fweight"
	nobs = (fw & !missing(n_used)) ? n_used : N

	linear = _isin(kind, ("regress", "areg", "xtreg_fe", "xtreg_re", "reghdfe", "ivregress", "ivreg2", "ivreghdfe"))
	ml = _isin(kind, ("ml", "glm"))
	endog = tokens(kind == "ivregress" ? _eg("endog") : _eg("instd"))
	iv = length(endog) > 0
	if (kind == "ivregress") {
		exogr = tokens(_eg("exogr"))
		insts = tokens(_eg("exog"))
		insts = length(exogr) ? select(insts, !_er_in(insts, exogr)) : insts
	}
	else insts = tokens(_eg("exexog"))
	absvars = tokens(kind == "areg" ? _eg("absvar") : (kind == "xtreg_fe" ? _eg("ivar") : _eg("absvars")))
	haveabs = length(absvars) > 0
	if (kind == "ivregress") small = _eg("small") == "small"
	else if (_isin(kind, ("regress", "areg", "xtreg_fe", "reghdfe"))) small = 1
	else if (_isin(kind, ("ivreg2", "ivreghdfe"))) small = !missing(dfr)
	else if (_isin(kind, ("xtreg_re", "ml", "glm"))) small = 0
	else small = !missing(dfr)
	dft = small ? dfr : .
	if (kind == "glm" | kind == "generic") dft = dfr

	// ---- vcov ----
	vce = strlower(_eg("vce"))
	clusters = tokens(_eg("clustvar"))
	ncl = length(clusters)
	if (ncl == 2) vtype = "twoway"
	else if (ncl > 2) vtype = "multiway"
	else if (ncl == 1) vtype = "CRV1"
	else if (_eg("kernel") != "") vtype = "HAC"
	else if (vce == "hc2") vtype = "HC2"
	else if (vce == "hc3") vtype = "HC3"
	else if (_isin(vce, ("oim", "opg", "eim"))) vtype = vce
	else if (strpos(vce, "robust")) vtype = kind == "generic" ? "robust" : ((linear & small) ? "HC1" : "HC0")
	else if (_isin(vce, ("", "ols", "unadjusted", "conventional"))) vtype = linear | kind == "generic" ? "iid" : "oim"
	else vtype = vce
	isiid = vtype == "iid"

	conv = "stata"
	formula = kcounts = ""
	if (kind == "reghdfe" | (kind == "ivreghdfe" & small & haveabs)) {
		conv = cmd
		// The worked converter's strings (converters/reghdfe), so its records and these compare equal
		formula = vtype == "CRV1" ? "(N-1)/(N-K) * G/(G-1), K = df_m + df_a" : (vtype == "HC1" ? "N/(N-K), K = df_m + df_a" : (isiid ? "s2 = RSS/(N-K), K = df_m + df_a" : ""))
		kcounts = "df_m regressors plus df_a absorbed levels (initial minus redundant minus nested in clusters)"
	}
	else if (linear & small) {
		conv = kind == "areg" ? "stata areg" : (kind == "xtreg_fe" ? "stata xtreg" : (kind == "regress" ? "stata" : (kind == "ivregress" ? "stata ivregress" : cmd)))
		formula = vtype == "CRV1" ? "(N-1)/(N-K) * G/(G-1)" : (vtype == "HC1" ? "N/(N-K)" : (isiid ? "s2 = RSS/(N-K)" : ""))
		if (kind == "areg") kcounts = "K = rank + df_a: absorbed levels counted even when nested in the clusters"
		else if (kind == "xtreg_fe") kcounts = vtype == "CRV1" ? "K = rank: the panels are nested in the clusters, so absorbed levels are not counted" : "K = rank + df_a"
		else kcounts = "K = rank"
	}
	else if (_isin(kind, ("ivregress", "ivreg2", "ivreghdfe"))) {
		conv = kind == "ivregress" ? "stata ivregress" : cmd
		formula = isiid ? "s2 = RSS/N" : ((vtype == "HC0" | vtype == "CRV1" | vtype == "twoway") ? "none: no N/(N-K), (N-1)/(N-K) or G/(G-1)" : "")
	}
	else if (kind == "xtreg_re") conv = "stata xtreg"
	else if (ml) {
		formula = _isin(vtype, ("oim", "opg", "eim")) ? "none" : (vtype == "HC0" ? "N/(N-1)" : (vtype == "CRV1" ? "G/(G-1)" : ""))
	}

	vrows = J(1, rows(V), "")
	for (i = 1; i <= rows(V); i++) vrows[i] = _ej_na(V[i, .])
	params = J(1, 0, "")
	cn = J(1, cols(b), "")
	eq1 = cs[1, 1]
	for (j = 1; j <= cols(b); j++) {
		eq = cs[j, 1]
		term = cs[j, 2]
		if (eq == "/") term = "/" + term
		cn[j] = term
	}

	vc = _on()
	_oa(vc, "kind", _ej_s("matrix"), 2)
	_oa(vc, "labels", _ej_sa(cn), 2)
	_oa(vc, "data", "[" + invtokens(vrows, ", ") + "]", 2)
	_oa(vc, "type", _ej_s(vtype), 2)
	_oa(vc, "tool_type", (vtype != vce & vce != "" ? _ej_s(vce) : ""), 2)
	_oa(vc, "cluster", (ncl ? _ej_sa(clusters) : ""), 3)
	if (ncl) {
		rn = J(1, ncl, "")
		for (i = 1; i <= ncl; i++) rn[i] = _ej_nx(ncl == 1 ? _e("N_clust") : _e(sprintf("N_clust%g", i)))
		_oa(vc, "n_clusters", _ej_o(clusters, rn), 3)
		_oa(vc, "n_clusters_min", _en("N_clust"), 3)
	}
	_oa(vc, "ssc", _ej_o(("convention", "formula", "K_counts", "factors"), (_ej_s(conv),
		(formula != "" ? _ej_s(formula) : ""), (kcounts != "" ? _ej_s(kcounts) : ""),
		(kind == "reghdfe" | (kind == "ivreghdfe" & haveabs) ? _ej_o(("dofmethod", "df_a", "df_a_nested", "df_a_redundant"),
			(_ej_s(_eg("dofmethod")), _en("df_a"), _en("df_a_nested"), _en("df_a_redundant"))) : ""))), 2)
	_oa(vc, "df_t", _ej_n(dft), 2)
	_oa(vc, "default", "true", 2)
	vcovs = _or(vc, lv)

	// The model-based vcov kept beside a robust or cluster one
	Vm = st_matrix("e(V_modelbased)")
	if (rows(Vm) == rows(V) & (kind == "regress" | ml)) {
		for (i = 1; i <= rows(Vm); i++) vrows[i] = _ej_na(Vm[i, .])
		vm = _on()
		_oa(vm, "kind", _ej_s("matrix"), 2)
		_oa(vm, "labels", _ej_sa(cn), 2)
		_oa(vm, "data", "[" + invtokens(vrows, ", ") + "]", 2)
		_oa(vm, "type", _ej_s(kind == "regress" ? "iid" : ((kind == "glm" & _eg("opt") == "irls") ? "eim" : "oim")), 2)
		_oa(vm, "tool_type", _ej_s("V_modelbased"), 2)
		_oa(vm, "ssc", _ej_o(("convention", "formula", "K_counts"), (_ej_s(conv),
			_ej_s(kind == "regress" ? "s2 = RSS/(N-K)" : "none"), (kind == "regress" ? _ej_s("K = rank") : ""))), 2)
		_oa(vm, "df_t", _ej_n(kind == "regress" ? N - rank : .), 2)
		_oa(vm, "default", "false", 2)
		vcovs = vcovs, _or(vm, lv)
	}

	// ---- parameters (from the default vcov; t with df_t, else z) ----
	crit = missing(dft) ? invnormal(1 - (1 - level / 100) / 2) : invttail(dft, (1 - level / 100) / 2)
	for (j = 1; j <= cols(b); j++) {
		eq = cs[j, 1]
		term = cn[j]
		canon = dropped = ""
		if (eq != "/") _er_term(cs[j, 2], canon, dropped)
		s = eq == "/" ? _ej_s("auxiliary") : ((eq != eq1 & eq != "") ? _ej_s(eq) : "")
		if (dropped != "") {
			params = params, _ej_o(("term", "canonical", "component", "dropped"), (_ej_s(term), canon, s, _ej_s(dropped)))
			continue
		}
		se = sqrt(V[j, j])
		t = b[j] / se
		// Unmapped commands: Stata tests no ancillary parameter of theirs we can't vouch for
		if (kind == "generic" & eq == "/") {
			params = params, _ej_o(("term", "component", "estimate", "std_error"), (_ej_s(term), s, _ej_n(b[j]), _ej_n(se)))
			continue
		}
		params = params, _ej_o(("term", "canonical", "component", "estimate", "std_error", "statistic", "p_value", "conf_low", "conf_high"),
			(_ej_s(term), canon, s, _ej_n(b[j]), _ej_n(se), _ej_n(t),
			 _ej_n(missing(dft) ? 2 * normal(-abs(t)) : 2 * ttail(dft, abs(t))),
			 _ej_n(b[j] - crit * se), _ej_n(b[j] + crit * se)))
	}

	// ---- convergence ----
	conv_ok = _e("converged")
	messages = J(1, 0, "")
	if (kind == "glm" & _eg("opt") == "irls") messages = messages, _ej_o(("level", "code", "source", "message"),
		(_ej_s("info"), _ej_s("convergence_unknown"), _ej_s("estrec"), _ej_s("glm, irls doesn't store whether it converged, so the record doesn't claim glm/0.1")))
	if (conv_ok == 0) messages = messages, _ej_o(("level", "code", "source", "message"),
		(_ej_s("warning"), _ej_s("not_converged"), _ej_s(cmd), _ej_s("convergence not achieved")))

	// ---- metrics ----
	nsing = _isin(kind, ("reghdfe", "ivreghdfe")) ? _e("num_singletons") : (_isin(kind, ("areg", "xtreg_fe")) ? 0 : .)
	metrics = _on()
	_oa(metrics, "nobs", _ej_def(_ej_n(nobs), fw ? "rows used; e(N) counts the frequency weights" : ""), 1)
	_oa(metrics, "nobs_full", _en("N_full"), 2)
	_oa(metrics, "n_singletons", _ej_nx(nsing), 2)
	dfdef = ""
	if (!missing(dfr)) {
		if (ncl & kind == "reghdfe") dfdef = "min(G) - 1 under clustering (reghdfe e(df_r))"
		else if (ncl) dfdef = (ncl == 1 ? "G - 1" : "min(G) - 1") + " under clustering (" + cmd + " e(df_r))"
		_oa(metrics, "df_residual", _ej_def(_ej_n(dfr), dfdef), 1)
	}
	else if (kind == "glm") _oa(metrics, "df_residual", _en("df"), 1)
	else if (linear) _oa(metrics, "df_residual", _ej_def(_ej_n(N - rank),
		"N - K, K = rank; " + (kind == "xtreg_re" ? "xtreg, re" : cmd) + " used z tests, so this df isn't used"), 1)
	_oa(metrics, "df_model", _ej_def(_en("df_m"), kind == "xtreg_fe" ? "regressors plus absorbed levels (xtreg, fe e(df_m))" : ""), 2)
	if (_isin(kind, ("areg", "xtreg_fe", "reghdfe", "ivreghdfe"))) {
		_oa(metrics, "df_absorbed", _en("df_a"), 2)
		_oa(metrics, "df_absorbed_nested", _en("df_a_nested"), 2)
	}
	if (linear) {
		s = (wtype == "aweight" & kind == "reghdfe") ? ", with aweights rescaled to sum to N" : ""
		_oa(metrics, "rss", _ej_def(_en("rss"), s != "" ? "weighted RSS" + s : ""), 2)
		if (_isin(kind, ("regress", "ivregress")) & !missing(_e("mss"))) _oa(metrics, "tss", _ej_n(_e("mss") + _e("rss")), 2)
		else if (kind != "xtreg_re") _oa(metrics, "tss", _en("tss"), 2)
		_oa(metrics, "tss_within", _en("tss_within"), 2)
		_oa(metrics, "r2", _en("r2"), 2)
		_oa(metrics, "adj_r2", _en("r2_a"), 2)
		_oa(metrics, "r2_within", (kind == "reghdfe" | kind == "ivreghdfe") ? _en("r2_within") : _en("r2_w"), 2)
		_oa(metrics, "adj_r2_within", _en("r2_a_within"), 2)
		_oa(metrics, "r2_between", _en("r2_b"), 2)
		_oa(metrics, "r2_overall", _en("r2_o"), 2)
		if (kind == "xtreg_re") _oa(metrics, "sigma", _ej_def(_en("sigma_e"), "sigma_e, the SD of the idiosyncratic error"), 2)
		else _oa(metrics, "sigma", _ej_def(_en("rmse"), small ? (s != "" ? "sqrt(RSS / (N - K))" + s : "") : "sqrt(RSS / N)"), 2)
		_oa(metrics, "sigma_fe", _en("sigma_u"), 2)
		_oa(metrics, "rho", _en("rho"), 2)
	}
	_oa(metrics, "log_lik", _en("ll"), 2)
	_oa(metrics, "log_lik_null", _en("ll_0"), 2)
	if (ml) {
		dev = .
		if (kind == "glm") dev = _e("deviance")
		else if (_isin(cmd, ("logit", "logistic", "probit"))) dev = -2 * _e("ll")
		else if (cmd == "poisson" | (cmd == "nbreg" & _eg("dispers") == "mean")) dev = _er_deviance(cmd, depvar, wvar, _e("alpha"))
		s = ""
		if (_isin(cmd, ("logit", "logistic", "probit"))) s = "-2 log_lik: a 0/1 outcome's saturated log-likelihood is 0"
		else if (cmd != "glm") s = "computed by estrec from predict, n" + (cmd == "nbreg" ? " and e(alpha)" : "")
		_oa(metrics, "deviance", _ej_def(_ej_nx(dev), s), 2)
		_oa(metrics, "pseudo_r2", _en("r2_p"), 2)
		if (!missing(_e("N_cds"))) _oa(metrics, "n_completely_determined", _ej_n(_e("N_cds") + _e("N_cdf")), 2)
		_oa(metrics, "alpha", _en("alpha"), 2)
		_oa(metrics, "aic", _ej_def(_en("aic"), "(-2 log_lik + 2 K) / N, per observation (Stata glm)"), 2)
		_oa(metrics, "bic", _ej_def(_en("bic"), "deviance - df_residual * ln(N) (Stata glm)"), 2)
		_oa(metrics, "dispersion", _en("phi"), 2)
		_oa(metrics, "pearson_chi2", _en("deviance_p"), 2)
	}
	if (iv) {
		_oa(metrics, "kappa", (kind == "ivregress" ? (_eg("estimator") == "liml" ? _en("kappa") : "") : _en("lambda")), 2)
		_oa(metrics, "fuller", _en("fuller"), 2)
	}
	_oa(metrics, "sum_weights", fw ? _ej_n(N) : _en("sumweights"), 2)
	_oa(metrics, "rank", _ej_nx(rank), 2)
	_oa(metrics, "conf_level", _ej_n(level / 100), 1)

	// ---- tests ----
	T.t = J(1, 0, "")
	T.n = 0
	if (!missing(_e("F"))) {
		if (_isin(kind, ("ivreg2", "ivreghdfe"))) _ta(T, "model", isiid ? "f" : "wald", _e("F"), "F", _e("Fdf1"), _e("Fdf2"), _e("Fp"), "estimation", "", "", "")
		else {
			// xtreg, fe counts the absorbed levels in e(df_m); its F test doesn't
			k = kind == "xtreg_fe" ? _e("df_m") - _e("df_a") : _e("df_m")
			_ta(T, "model", isiid ? "f" : "wald", _e("F"), "F", k, dfr, Ftail(k, dfr, _e("F")), "estimation", "", "", "")
		}
	}
	else if (!missing(_e("chi2"))) {
		s = strlower(_eg("chi2type"))
		_ta(T, "model", s == "lr" ? "likelihood_ratio" : "wald", _e("chi2"), "chi2", _e("df_m"), ., chi2tail(_e("df_m"), _e("chi2")), "estimation", "", "", "")
	}
	if (kind == "xtreg_fe") _ta(T, "fixed_effects", "f", _e("F_f"), "F", _e("df_a"), dfr, _e("p_f"), "estimation", "", "", "")
	if (iv & _isin(kind, ("ivreg2", "ivreghdfe"))) {
		_ta(T, "underidentification", isiid ? "anderson_lm" : "kleibergen_paap_rk_lm", _e("idstat"), "chi2", _e("iddf"), ., _e("idp"), "estimation", "", "", "")
		_ta(T, "weak_identification", "cragg_donald_f", _e("cdf"), "", ., ., ., "estimation", "", "", "")
		if (!isiid) _ta(T, "weak_identification", "kleibergen_paap_rk_wald_f", _e("rkf"), "", ., ., ., "estimation", "", "", "")
		_ta(T, "weak_identification", "anderson_rubin", _e("arf"), "F", _e("ardf"), _e("ardf_r"), _e("arfp"), "estimation", "", "", "")
		_ta(T, "weak_identification", "anderson_rubin", _e("archi2"), "chi2", _e("ardf"), ., _e("archi2p"), "estimation", "", "", "")
		_ta(T, "weak_identification", "stock_wright", _e("sstat"), "chi2", _e("sstatdf"), ., _e("sstatp"), "estimation", "", "", "")
		if (_e("jdf") > 0) _ta(T, "overidentification", isiid ? "sargan" : "hansen_j", _e("j"), "chi2", _e("jdf"), ., _e("jp"), "estimation", "", "", "")
		_ta(T, "endogeneity", "c", _e("estat"), "chi2", _e("estatdf"), ., _e("estatp"), "estimation", "", "", "")
	}

	// ---- first stage ----
	perendog = J(1, 0, "")
	if (iv & _isin(kind, ("ivreg2", "ivreghdfe"))) {
		M = st_matrix("e(first)")
		if (rows(M)) {
			rn = st_matrixrowstripe("e(first)")[., 2]'
			fcn = st_matrixcolstripe("e(first)")[., 2]'
			for (k = 1; k <= cols(M); k++) {
				_ta(T, "first_stage", isiid ? "f" : "wald", _er_row(M, rn, "F", k), "F", _er_row(M, rn, "df", k), _er_row(M, rn, "df_r", k), _er_row(M, rn, "pvalue", k), "estimation", fcn[k], "", "")
				_ta(T, "first_stage", "sanderson_windmeijer_f", _er_row(M, rn, "SWF", k), "F", _er_row(M, rn, "SWFdf1", k), _er_row(M, rn, "SWFdf2", k), _er_row(M, rn, "SWFp", k), "estimation", fcn[k], "", "")
				_ta(T, "first_stage", "angrist_pischke_f", _er_row(M, rn, "APF", k), "F", _er_row(M, rn, "APFdf1", k), _er_row(M, rn, "APFdf2", k), _er_row(M, rn, "APFp", k), "estimation", fcn[k], "", "")
				perendog = perendog, _ej_o(("endogenous", "partial_r2", "shea_partial_r2"),
					(_ej_s(fcn[k]), _ej_nx(_er_row(M, rn, "pr2", k)), _ej_nx(_er_row(M, rn, "sheapr2", k))))
			}
		}
	}
	if (iv & kind == "ivregress" & doestat) _er_estat(T, perendog, endog, isiid, lv)

	// ---- specification ----
	sample = _on()
	n_missing = rows_input - n_complete
	n_other = rows_input - n_missing - (missing(n_used) ? N : n_used) - (missing(nsing) ? 0 : nsing)
	_oa(sample, "restriction", "null", 3)
	_oa(sample, "rows_input", _ej_n(rows_input), 3)
	_oa(sample, "dropped", _ej_o(("missing", "singletons", "other"),
		(_ej_n(n_missing), _ej_nx(nsing), (n_other > 0 ? _ej_n(n_other) : ""))), 3)

	opts = _on()
	if (_isin(kind, ("reghdfe", "ivreghdfe"))) _oa(opts, "drop_singletons", _ej_b(_e("drop_singletons")), 3)
	else if (_isin(kind, ("areg", "xtreg_fe"))) _oa(opts, "drop_singletons", "false", 3)
	if (kind == "ivregress") _oa(opts, "small", _ej_b(small), 3)
	if (cmd == "nbreg") _oa(opts, "dispersion", _ej_s(_eg("dispers")), 3)
	if (kind == "glm") _oa(opts, "algorithm", _ej_s(_eg("opt") == "irls" ? "irls" : "ml"), 3)

	s = _eg("offset")
	spec = _on()
	_oa(spec, "call", _ej_s(st_local("call")), 3)
	_oa(spec, "formula", _ej_o(("text", "syntax"), (_ej_s(_er_formula(_eg("cmdline"), absvars, kind)), _ej_s("stata"))), 3)
	_oa(spec, "terms", _ej_sa(_er_terms(cs)), 3)
	_oa(spec, "weights", (wtype == "" ? "null" : _ej_o(("variable", "type"), (_ej_s(wvar),
		_ej_s(wtype == "aweight" ? "analytic" : (wtype == "fweight" ? "frequency" : (wtype == "pweight" ? "probability" : (wtype == "iweight" ? "importance" : wtype))))))), 3)
	if (haveabs) _oa(spec, "fixed_effects", _ej_sa(absvars), 3)
	_oa(spec, "clusters", ncl ? _ej_sa(clusters) : "[]", 3)
	if (iv) {
		_oa(spec, "endogenous", _ej_sa(endog), 3)
		_oa(spec, "instruments", _ej_sa(insts), 3)
	}
	if (ml) _oa(spec, "offset", (s == "" ? "null" : (regexm(s, "^ln\((.*)\)$") ?
		_ej_o(("variable", "exposure"), (_ej_s(regexs(1)), "true")) : _ej_o(("variable", "exposure"), (_ej_s(s), "false")))), 3)
	_oa(spec, "sample", _or(sample, lv), 3)
	if (_isin(kind, ("xtreg_fe", "xtreg_re"))) _oa(spec, "state", _ej_o("xtset", _ej_o(("panelvar", "timevar"),
		(_ej_s(st_local("iis")), (st_local("tis") != "" ? _ej_s(st_local("tis")) : "")))), 3)
	_oa(spec, "options", _or(opts, lv) != "" ? _or(opts, lv) : "", 3)

	// ---- structures ----
	fe = J(1, 0, "")
	if (_isin(kind, ("reghdfe", "ivreghdfe"))) {
		dof = st_matrix("e(dof_table)")
		if (rows(dof)) {
			rs = st_matrixrowstripe("e(dof_table)")
			for (i = 1; i <= rows(dof); i++) {
				fe = fe, _ej_o(("kind", "name", "levels", "redundant", "redundant_method", "nested_in", "constant_reported"),
					(_ej_s("object"), _ej_s(rs[i, 2]), _ej_n(dof[i, 1]), _ej_n(dof[i, 2]),
					 (dof[i, 2] > 0 ? _ej_s(dof[i, 5] == 1 ? "nested" : (dof[i, 4] == 1 ? "pairwise" : "exact")) : ""),
					 ((dof[i, 5] == 1 & ncl) ? _ej_sa(clusters) : ""), _ej_b(_e("report_constant") == 1)))
			}
		}
	}
	else if (kind == "areg") fe = _ej_o(("kind", "name", "levels", "constant_reported"),
		(_ej_s("object"), _ej_s(absvars[1]), _en("k_absorb"), "true"))
	else if (kind == "xtreg_fe") fe = _ej_o(("kind", "name", "levels", "group_size", "nested_in", "constant_reported"),
		(_ej_s("object"), _ej_s(absvars[1]), _en("N_g"),
		 _ej_o(("min", "mean", "max"), (_en("g_min"), _en("g_avg"), _en("g_max"))),
		 (ncl ? _ej_sa(clusters) : ""), "true"))

	num = _on()
	if (kind == "reghdfe") {
		_oa(num, "kind", _ej_s("object"), 4)
		_oa(num, "iterative", "true", 4)
		_oa(num, "iterations", _en("ic"), 4)
		_oa(num, "converged", _ej_b(conv_ok), 4)
	}
	else if (ml) {
		_oa(num, "kind", _ej_s("object"), 4)
		_oa(num, "iterative", "true", 4)
		_oa(num, "algorithm", (_eg("opt") == "irls" ? _ej_s("irls") : (_eg("technique") != "" ? _ej_s(_eg("technique")) : "")), 4)
		_oa(num, "iterations", _en("ic"), 4)
		_oa(num, "converged", missing(conv_ok) ? "" : _ej_b(conv_ok), 4)
	}

	structures = _on()
	_oa(structures, "vcov", _ej_l(vcovs), 2)
	_oa(structures, "fixed_effects", _ej_l(fe), 3)
	_oa(structures, "first_stage", length(perendog) ? _ej_o(("kind", "per_endogenous"), (_ej_s("object"), _ej_l(perendog))) : "", 2)
	_oa(structures, "numerics", _or(num, lv), 4)

	// ---- provenance ----
	src = _isin(cmd, ("reghdfe", "ivreghdfe", "ivreg2")) ? "SSC" : "Stata"
	software = _ej_o(("name", "version", "purl", "role", "source"), (_ej_s(cmd),
		(ver_cmd != "" ? _ej_s(ver_cmd) : _ej_s(strofreal(c("stata_version")))),
		(src == "SSC" & ver_cmd != "" ? _ej_s("pkg:generic/" + cmd + "@" + ver_cmd) : ""), _ej_s("estimator"), _ej_s(src)))
	software = software, _ej_o(("name", "version", "purl", "role", "attributes"), (_ej_s("stata"), _ej_s(strofreal(c("stata_version"))),
		_ej_s("pkg:generic/stata@" + strofreal(c("stata_version"))), _ej_s("language"),
		(lv >= 5 ? _ej_o(("edition", "born_date", "processors"), (_ej_s(c("edition_real")), _ej_s(c("born_date")), _ej_n(c("processors")))) : "")))
	software = software, _ej_o(("name", "version", "role"), (_ej_s("estrec"), _ej_s(wver), _ej_s("writer")))
	if (lv >= 5) {
		if (_isin(cmd, ("reghdfe", "ivreghdfe"))) software = software, _er_dep("ftools", st_local("ver_ftools"))
		if (cmd == "ivreghdfe") software = software, _er_dep("ivreg2", st_local("ver_ivreg2"))
		if (_isin(cmd, ("ivreg2", "ivreghdfe"))) software = software, _er_dep("ranktest", st_local("ver_ranktest"))
	}
	s = st_local("datasig")
	prov = _on()
	_oa(prov, "software", _ej_l(software), 4)
	_oa(prov, "environment", _ej_o(("os", "machine", "random"), (_ej_s(c("os")), _ej_s(c("machine_type")), _ej_o("rngtype", _ej_s(c("rngtype"))))), 5)
	_oa(prov, "data", "[" + _ej_o(("role", "location", "rows", "columns", "checksum"),
		(_ej_s("estimation"), (ident & lv >= 5 & c("filename") != "" ? _ej_s(c("filename")) : ""), _ej_n(rows_input), st_local("nvars"),
		 (s != "" ? _ej_o(("algorithm", "value", "of", "method"), (_ej_s("datasignature"), _ej_s(s), _ej_s("in-memory"), _ej_s("Stata datasignature (rows, columns, names, contents)"))) : ""))) + "]", 4)
	if (ident) _oa(prov, "agent", _ej_o(("user", "host"), (_ej_s(c("username")), _ej_s(c("hostname")))), 5)

	// ---- meta ----
	profiles = J(1, 0, "")
	if (lv >= 2 & (linear | (kind == "glm"))) profiles = profiles, "inference/0.1"
	if (lv >= 3 & iv) profiles = profiles, "iv/0.1"
	if (lv >= 3 & _isin(kind, ("areg", "xtreg_fe", "reghdfe", "ivreghdfe"))) profiles = profiles, "linear-fe/0.1"
	if (lv >= 4 & ml & !missing(conv_ok)) profiles = profiles, "glm/0.1"
	if (kind == "generic") messages = messages, _ej_o(("level", "code", "source", "message"),
		(_ej_s("info"), _ej_s("no_profile"), _ej_s("estrec"), _ej_s("estrec has no mapping for " + cmd + ": core fields only, no profiles claimed")))
	if (!missing(nsing) & nsing > 0) messages = messages, _ej_o(("level", "code", "source", "message"),
		(_ej_s("info"), _ej_s("singletons"), _ej_s(cmd), _ej_s(strofreal(nsing) + " singleton rows dropped")))

	est = _on()
	_er_estimator(est, kind, cmd, iv)
	meta = _on()
	if (lv == 1) created = substr(created, 1, 10)   // a date, not a time
	_oa(meta, "id", _ej_s(_er_uuid()), 1)
	_oa(meta, "created", _ej_s(created), 1)
	_oa(meta, "status", _ej_s(conv_ok == 0 ? "warning" : "ok"), 1)
	_oa(meta, "estimator", _or(est, lv), 2)
	_oa(meta, "responses", _ej_sa(tokens(depvar)), 2)
	_oa(meta, "profiles", length(profiles) ? _ej_sa(profiles) : "", 1)
	_oa(meta, "disclosure", _ej_o("level", _ej_n(lv)), 1)
	_oa(meta, "producer", _ej_o(("name", "version"), (_ej_s("estrec"), _ej_s(wver))), 4)
	_oa(meta, "messages", _ej_l(messages), 2)

	sections = ("meta", "metrics", "parameters")
	if (lv >= 3) sections = sections, "specification"
	if (lv >= 2) sections = sections, "structures"
	if (lv >= 4) sections = sections, "provenance"
	if (lv >= 2 & T.n) sections = sections, "tests"
	histk = ("when", "by", "action", "level", "sections")
	histv = (_ej_s(created), (lv >= 4 ? _ej_o(("name", "version"), (_ej_s("estrec"), _ej_s(wver))) : ""),
		_ej_s("created"), _ej_n(lv), (lv >= 2 ? _ej_sa(sections) : ""))

	nl = char(10)
	rec = "{" + nl +
		" " + _ej_s("schema") + ": " + _ej_s("estimation/0.1") + "," + nl +
		" " + _ej_s("meta") + ": " + _or(meta, lv) + "," + nl +
		(lv >= 3 ? " " + _ej_s("specification") + ": " + _or(spec, lv) + "," + nl : "") +
		" " + _ej_s("metrics") + ": " + _or(metrics, lv) + "," + nl +
		" " + _ej_s("parameters") + ": [" + nl + "  " + invtokens(params, "," + nl + "  ") + nl + " ]," + nl +
		(lv >= 2 ? " " + _ej_s("structures") + ": " + _or(structures, lv) + "," + nl : "") +
		(lv >= 2 & T.n ? " " + _ej_s("tests") + ": [" + nl + "  " + invtokens(T.t, "," + nl + "  ") + nl + " ]," + nl : "") +
		(lv >= 4 ? " " + _ej_s("provenance") + ": " + _or(prov, lv) + "," + nl : "") +
		" " + _ej_s("history") + ": [" + _ej_o(histk, histv) + "]" + nl + "}" + nl

	if (fileexists(fn)) {
		if (!replace) {
			errprintf("file %s already exists; use replace\n", fn)
			exit(602)
		}
		unlink(fn)
	}
	fh = fopen(fn, "w")
	fwrite(fh, rec)
	fclose(fh)
}

// Which elements of a are in b
real rowvector _er_in(string rowvector a, string rowvector b)
{
	real rowvector r
	real scalar i
	r = J(1, length(a), 0)
	for (i = 1; i <= length(a); i++) r[i] = anyof(b, a[i])
	return(r)
}

// Row `name' of column k of a matrix with row names rn, or missing
real scalar _er_row(real matrix M, string rowvector rn, string scalar name, real scalar k)
{
	real scalar i
	for (i = 1; i <= length(rn); i++) if (rn[i] == name) return(M[i, k])
	return(.)
}

string rowvector _er_terms(string matrix cs)
{
	string rowvector r
	real scalar j
	r = J(1, rows(cs), "")
	for (j = 1; j <= rows(cs); j++) r[j] = (cs[j, 1] == "/" ? "/" : "") + cs[j, 2]
	return(r)
}

// The model as written: the command line without the command, weights, if/in and options
string scalar _er_formula(string scalar cmdline, string rowvector absvars, string scalar kind)
{
	string scalar s
	s = cmdline
	if (strpos(s, ",")) s = substr(s, 1, strpos(s, ",") - 1)
	s = ustrregexra(s, "\[[^\]]*\]", "")
	s = ustrregexra(s, "\s(if|in)\s.*$", "")
	s = ustrregexra(s, "^\s*\S+\s+(2sls|liml|gmm)?\s*", "")
	s = strtrim(stritrim(s))
	if (length(absvars) & kind != "xtreg_fe") s = s + ", absorb(" + invtokens(absvars) + ")"
	return(s)
}

void _er_estimator(struct erobj scalar est, string scalar kind, string scalar cmd, real scalar iv)
{
	string scalar m, d, l
	if (kind == "generic") return
	if (kind == "ml" | kind == "glm") {
		_oa(est, "family", _ej_s("glm"), 2)
		_oa(est, "method", _ej_s(kind == "glm" & _eg("opt") == "irls" ? "irls" : "mle"), 2)
		if (_isin(cmd, ("logit", "logistic"))) { d = "binomial"; l = "logit"; }
		else if (cmd == "probit") { d = "binomial"; l = "probit"; }
		else if (cmd == "poisson") { d = "poisson"; l = "log"; }
		else if (cmd == "nbreg") { d = "negative_binomial"; l = "log"; }
		else {
			d = strlower(_eg("varfunct"))
			d = d == "bernoulli" ? "binomial" : (d == "neg. binomial" ? "negative_binomial" : (d == "inverse gaussian" ? "inverse_gaussian" : d))
			l = strlower(_eg("linkt"))
			l = l == "neg. binomial" ? "negative_binomial" : (l == "log-log" ? "loglog" : (l == "log-compl" ? "logc" : (l == "reciprocal" ? "inverse" : l)))
		}
		_oa(est, "distribution", _ej_s(d), 2)
		_oa(est, "link", _ej_s(l), 2)
		return
	}
	_oa(est, "family", _ej_s("linear"), 2)
	m = "ols"
	if (kind == "ivregress") m = _eg("estimator")
	else if (iv) {
		m = _eg("model")
		m = m == "iv" ? "2sls" : (m == "gmm2s" ? "gmm" : m)
		if (!missing(_e("fuller"))) m = "fuller"
	}
	else if (kind == "xtreg_re") m = "gls"
	_oa(est, "method", _ej_s(m), 2)
	if (kind == "xtreg_re") _oa(est, "panel", _ej_s("random_effects"), 2)
	if (kind == "xtreg_fe") _oa(est, "panel", _ej_s("fixed_effects"), 2)
}

string scalar _er_dep(string scalar name, string scalar ver)
{
	return(_ej_o(("name", "version", "purl", "role", "source"), (_ej_s(name), (ver != "" ? _ej_s(ver) : ""),
		(ver != "" ? _ej_s("pkg:generic/" + name + "@" + ver) : ""), _ej_s("dependency"), _ej_s("SSC"))))
}

// Poisson or NB2 deviance over e(sample), from predict, n
real scalar _er_deviance(string scalar cmd, string scalar y, string scalar w, real scalar alpha)
{
	string scalar mu, ts
	real colvector Y, MU, W, d
	real scalar dev
	mu = st_tempname()
	ts = st_tempname()
	if (_stata("quietly predict double " + mu + " if e(sample), n", 1)) return(.)
	stata("quietly generate byte " + ts + " = e(sample)")
	Y = st_data(., y, ts)
	MU = st_data(., mu, ts)
	W = (w != "" ? st_data(., w, ts) : J(rows(Y), 1, 1))
	if (cmd == "poisson") d = (Y :> 0) :* Y :* ln(Y :/ MU) - (Y - MU)
	else d = (Y :> 0) :* Y :* ln(Y :/ MU) - (Y :+ 1 / alpha) :* ln((1 :+ alpha * Y) :/ (1 :+ alpha * MU))
	dev = 2 * quadsum(W :* editmissing(d, 0))
	st_dropvar((mu, ts))
	return(dev)
}

// ivregress first-stage, overidentification and endogeneity tests (estat)
void _er_estat(struct ertests scalar T, string rowvector perendog, string rowvector endog,
	real scalar isiid, real scalar lv)
{
	real matrix S, Mu
	real scalar k, mineig, df
	string scalar s

	s = lv < 4 ? "" : _ej_o(("name", "version", "call"), (_ej_s("stata"), _ej_s(strofreal(c("stata_version"))), _ej_s("estat firststage, all")))
	if (!_stata("quietly estat firststage, all", 1)) {
		mineig = _sc("r(mineig)")
		S = st_matrix("r(singleresults)")
		Mu = st_matrix("r(multiresults)")
		for (k = 1; k <= rows(S) & k <= length(endog); k++) {
			_ta(T, "first_stage", isiid ? "f" : "wald", S[k, 4], "F", S[k, 5], S[k, 6], S[k, 7], "postestimation", endog[k], "", s)
			perendog = perendog, _ej_o(("endogenous", "r2", "partial_r2", "shea_partial_r2"),
				(_ej_s(endog[k]), _ej_nx(S[k, 1]), _ej_nx(S[k, 3]), (rows(Mu) >= k ? _ej_nx(Mu[k, 1]) : "")))
		}
		_ta(T, "weak_identification", "cragg_donald_f", mineig, "", ., ., ., "postestimation", "", "minimum eigenvalue statistic", s)
	}
	s = lv < 4 ? "" : _ej_o(("name", "version", "call"), (_ej_s("stata"), _ej_s(strofreal(c("stata_version"))), _ej_s("estat overid")))
	if (!_stata("quietly estat overid", 1)) {
		df = _sc("r(df)")
		_ta(T, "overidentification", "sargan", _sc("r(sargan)"), "chi2", df, ., _sc("r(p_sargan)"), "postestimation", "", "", s)
		if (missing(_sc("r(basmann_df_n)"))) _ta(T, "overidentification", "basmann", _sc("r(basmann)"), "chi2", df, ., _sc("r(p_basmann)"), "postestimation", "", "", s)
		else _ta(T, "overidentification", "basmann", _sc("r(basmann)"), "F", _sc("r(basmann_df_n)"), _sc("r(basmann_df_d)"), _sc("r(p_basmann)"), "postestimation", "", "", s)
		if (missing(_sc("r(sargan)"))) _ta(T, "overidentification", "score", _sc("r(score)"), "chi2", df, ., _sc("r(p_score)"), "postestimation", "", "", s)
		_ta(T, "overidentification", "hansen_j", _sc("r(HansenJ)"), "chi2", _sc("r(J_df)"), ., _sc("r(p_HansenJ)"), "postestimation", "", "", s)
		_ta(T, "overidentification", "anderson_rubin", _sc("r(ar)"), "chi2", _sc("r(ar_df)"), ., _sc("r(p_ar)"), "postestimation", "", "", s)
	}
	s = lv < 4 ? "" : _ej_o(("name", "version", "call"), (_ej_s("stata"), _ej_s(strofreal(c("stata_version"))), _ej_s("estat endogenous")))
	if (!_stata("quietly estat endogenous", 1)) {
		df = _sc("r(df)")
		_ta(T, "endogeneity", "durbin", _sc("r(durbin)"), "chi2", df, ., _sc("r(p_durbin)"), "postestimation", "", "", s)
		_ta(T, "endogeneity", "wu_hausman", _sc("r(wu)"), "F", df, _sc("r(wudf_r)"), _sc("r(p_wu)"), "postestimation", "", "", s)
		_ta(T, "endogeneity", "score", _sc("r(r_score)"), "chi2", df, ., _sc("r(p_r_score)"), "postestimation", "", "robust score", s)
		_ta(T, "endogeneity", "f", _sc("r(regF)"), "F", _sc("r(regFdf_n)"), _sc("r(regFdf_d)"), _sc("r(p_regF)"), "postestimation", "", "robust regression-based", s)
	}
}

string scalar _er_uuid()
{
	transmorphic state
	real rowvector h
	string scalar s
	real scalar i
	state = rngstate()
	rseed(floor(runiform(1, 1) * 1e9) + clock(c("current_date") + " " + c("current_time"), "DMYhms") / 1000)
	h = floor(runiform(1, 16) * 256)
	rngstate(state)
	h[7] = mod(h[7], 16) + 64      // version 4
	h[9] = mod(h[9], 64) + 128     // variant 10xx
	s = ""
	for (i = 1; i <= 16; i++) {
		s = s + (h[i] < 16 ? "0" : "") + inbase(16, h[i])
		if (i == 4 | i == 6 | i == 8 | i == 10) s = s + "-"
	}
	return(s)
}

end
