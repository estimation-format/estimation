*! version 0.1.0  estimation_write: reghdfe e() -> estimation record (linear-fe/0.1)
*
* A worked converter: run it right after reghdfe to write the fit as an `estimation`
* record (JSON). Written against reghdfe 6.13.1 / ftools 2.50.0 on Stata 18.
*
*   reghdfe y x1 x2, absorb(firm year) vce(cluster firm)
*   estimation_write using "fit.estimation.json", replace
*
* Options:
*   replace             overwrite the file
*   noidentifying       leave out user, host and the data file's path
*   nodatasignature     skip the in-memory data checksum (datasignature)
*   call(string)        the command as written (default: e(cmdline))
*
* The record has no core digest (meta.core_digest is optional): computing it needs RFC 8785
* canonical JSON. Add it with the reference validator: `estimation digest --write FILE`.
* Timestamps come from the operating system's UTC clock (Stata has none); the record id is
* drawn from Mata's generator with the user's RNG state saved and restored.

program define estimation_write
	version 16
	syntax using/ [, REPLACE noIDENTifying noDATASIGnature CALL(string asis)]

	if "`e(cmd)'" != "reghdfe" {
		di as err "estimation_write: run it right after reghdfe (e(cmd) is `e(cmd)')"
		exit 301
	}
	if "`e(model)'" != "ols" {
		di as err "estimation_write: only OLS reghdfe fits (e(model) is `e(model)')"
		exit 198
	}
	if `"`call'"' == "" local call `"`e(cmdline)'"'

	* The data as the user has it, before any temporary variable is added
	local nvars = c(k)
	if "`datasignature'" == "" {
		quietly datasignature
		local datasig "`r(datasignature)'"
	}

	* Rows dropped for missing values: the model's variables, marked out over the whole data
	local names `e(depvar)' `e(indepvars)' `e(absvars)' `e(clustvar)'
	local wvar = trim(subinstr("`e(wexp)'", "=", "", 1))
	local names `names' `wvar'
	local names = ustrregexra("`names'", "[#.]", " ")
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

	* Versions from the first line of each package's ado file
	foreach p in reghdfe ftools {
		local ver_`p'
		capture findfile `p'.ado
		if !_rc {
			tempname fh
			file open `fh' using `"`r(fn)'"', read text
			file read `fh' line
			file close `fh'
			if ustrregexm(`"`line'"', "version ([0-9][0-9.]*)") local ver_`p' = ustrregexs(1)
		}
	}

	* UTC time from the OS
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
		di as err "estimation_write: couldn't read the UTC time from the operating system"
		exit 198
	}

	mata: _est_write(`"`using'"', "`replace'" != "", "`identifying'" == "", `"`call'"', ///
		"`created'", `n_complete', `nvars', "`datasig'", "`ver_reghdfe'", "`ver_ftools'")
	di as txt `"estimation record written to {browse "`using'"}"'
end


version 16
mata:
mata set matastrict on

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

// e() scalar, or missing when it isn't set (st_numscalar returns 0 x 0 then)
real scalar _est_sc(string scalar name)
{
	real matrix x
	x = st_numscalar(name)
	return(rows(x) ? x : .)
}

// An e() scalar as JSON, or "" (left out) when it isn't set or is missing
string scalar _est_num(string scalar name)
{
	real scalar x
	x = _est_sc("e(" + name + ")")
	return(missing(x) ? "" : _ej_n(x))
}

string scalar _est_uuid()
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

// One reghdfe column name -> (canonical JSON, dropped reason or "")
void _est_term(string scalar term, string scalar canon, string scalar dropped)
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

void _est_write(string scalar fn, real scalar replace, real scalar ident, string scalar call,
	string scalar created, real scalar n_complete, real scalar nvars, string scalar datasig,
	string scalar ver_reghdfe, string scalar ver_ftools)
{
	real matrix b, V, dof
	string matrix cs, rs
	string vector terms, clusters, absvars, fe, params, vrows, software, sections, dofrows
	string scalar canon, dropped, vce, vtype, wtype, wvar, dfr_def, meta, spec, metrics
	string scalar structures, provenance, history, rec, sample, nested, vcov, datain, messages, nl
	string vector clk, clv
	real scalar i, j, N, Nfull, nsing, rows_input, n_missing, n_other, df, se, t, crit, level
	real scalar fh, ncl

	b = st_matrix("e(b)")
	V = st_matrix("e(V)")
	cs = st_matrixcolstripe("e(b)")
	terms = cs[., 2]'
	N = _est_sc("e(N)")
	nsing = _est_sc("e(num_singletons)")
	Nfull = _est_sc("e(N_full)")
	if (missing(Nfull)) Nfull = N + nsing
	rows_input = st_nobs()
	n_missing = rows_input - n_complete
	n_other = rows_input - Nfull - n_missing   // if/in restrictions
	df = _est_sc("e(df_r)")
	level = c("level")
	crit = invttail(df, (1 - level / 100) / 2)
	clusters = tokens(st_global("e(clustvar)"))
	absvars = tokens(st_global("e(absvars)"))

	// Parameters, with the statistics reghdfe displays (t with e(df_r))
	params = J(1, 0, "")
	for (j = 1; j <= length(terms); j++) {
		canon = dropped = ""
		_est_term(terms[j], canon, dropped)
		if (dropped != "") {
			params = params, _ej_o(("term", "canonical", "dropped"), (_ej_s(terms[j]), canon, _ej_s(dropped)))
			continue
		}
		se = sqrt(V[j, j])
		t = b[j] / se
		params = params, _ej_o(("term", "canonical", "estimate", "std_error", "statistic", "p_value", "conf_low", "conf_high"),
			(_ej_s(terms[j]), canon, _ej_n(b[j]), _ej_n(se), _ej_n(t), _ej_n(2 * ttail(df, abs(t))),
			 _ej_n(b[j] - crit * se), _ej_n(b[j] + crit * se)))
	}

	// Default (and only) vcov
	vce = st_global("e(vce)")
	vtype = (vce == "unadjusted" | vce == "ols") ? "iid" : (vce == "robust" ? "HC1" : (vce == "cluster" ? "CRV1" : vce))
	vrows = J(1, rows(V), "")
	for (i = 1; i <= rows(V); i++) vrows[i] = _ej_na(V[i, .])
	ncl = length(clusters)
	clk = J(1, ncl, ""); clv = J(1, ncl, "")
	for (i = 1; i <= ncl; i++) {
		clk[i] = clusters[i]
		clv[i] = _ej_n(_est_sc(sprintf("e(N_clust%g)", i)))
	}
	vcov = _ej_o(("kind", "labels", "data", "type", "tool_type", "cluster", "n_clusters", "n_clusters_min", "ssc", "df_t", "default"),
		(_ej_s("matrix"), _ej_sa(terms), "[" + invtokens(vrows, ", ") + "]", _ej_s(vtype),
		 (vtype != vce ? _ej_s(vce) : ""),
		 (ncl ? _ej_sa(clusters) : ""), (ncl ? _ej_o(clk, clv) : ""), (ncl ? _est_num("N_clust") : ""),
		 _ej_o(("convention", "formula", "factors", "K_counts"),
			(_ej_s("reghdfe"),
			 _ej_s(vtype == "CRV1" ? "(N-1)/(N-K) * G/(G-1), K = df_m + df_a" : (vtype == "HC1" ? "N/(N-K), K = df_m + df_a" : "s2 = RSS/(N-K), K = df_m + df_a")),
			 _ej_o(("dofmethod", "df_a", "df_a_nested", "df_a_redundant"),
				(_ej_s(st_global("e(dofmethod)")), _est_num("df_a"), _est_num("df_a_nested"), _est_num("df_a_redundant"))),
			 _ej_s("df_m regressors plus df_a absorbed levels (initial minus redundant minus nested in clusters)"))),
		 _ej_n(df), "true"))

	// Fixed effects, from e(dof_table): Categories, Redundant, Num Coefs, Inexact?, Nested?
	fe = J(1, 0, "")
	dof = st_matrix("e(dof_table)")
	if (rows(dof)) {
		rs = st_matrixrowstripe("e(dof_table)")
		dofrows = rs[., 2]'
		for (i = 1; i <= rows(dof); i++) {
			nested = (dof[i, 5] == 1 & ncl) ? _ej_sa(clusters) : ""
			fe = fe, _ej_o(("kind", "name", "levels", "redundant", "redundant_method", "nested_in", "constant_reported"),
				(_ej_s("object"), _ej_s(dofrows[i]), _ej_n(dof[i, 1]), _ej_n(dof[i, 2]),
				 (dof[i, 2] > 0 ? _ej_s(dof[i, 5] == 1 ? "nested" : (dof[i, 4] == 1 ? "pairwise" : "exact")) : ""),
				 nested, _ej_b(_est_sc("e(report_constant)"))))
		}
	}

	dfr_def = ncl ? "min(G) - 1 under clustering (reghdfe e(df_r))" : ""
	metrics = _ej_o(("nobs", "nobs_full", "n_singletons", "df_residual", "df_model", "df_absorbed", "df_absorbed_nested",
		"rss", "tss", "tss_within", "r2", "adj_r2", "r2_within", "adj_r2_within", "sigma", "log_lik", "log_lik_null",
		"f_stat", "sum_weights", "rank", "conf_level"),
		(_ej_n(N), _ej_n(Nfull), _ej_n(nsing),
		 (ncl ? _ej_o(("value", "definition"), (_ej_n(df), _ej_s(dfr_def))) : _ej_n(df)),
		 _est_num("df_m"), _est_num("df_a"), _est_num("df_a_nested"), _est_num("rss"), _est_num("tss"),
		 _est_num("tss_within"), _est_num("r2"), _est_num("r2_a"), _est_num("r2_within"), _est_num("r2_a_within"),
		 _est_num("rmse"), _est_num("ll"), _est_num("ll_0"), _est_num("F"),
		 (missing(_est_sc("e(sumweights)")) ? "" : _est_num("sumweights")), _est_num("rank"),
		 _ej_n(level / 100)))

	wtype = st_global("e(wtype)")
	wvar = strtrim(subinstr(st_global("e(wexp)"), "=", "", 1))
	sample = _ej_o(("restriction", "rows_input", "dropped"),
		("null", _ej_n(rows_input),
		 _ej_o(("missing", "singletons", "other"), (_ej_n(n_missing), _ej_n(nsing), (n_other > 0 ? _ej_n(n_other) : "")))))
	spec = _ej_o(("call", "formula", "terms", "weights", "fixed_effects", "clusters", "sample", "options"),
		(_ej_s(call),
		 _ej_o(("text", "syntax"), (_ej_s(strtrim(st_global("e(depvar)") + " " + st_global("e(indepvars)")) + ", absorb(" + st_global("e(absvars)") + ")"), _ej_s("stata"))),
		 _ej_sa(terms),
		 (wtype == "" ? "null" : _ej_o(("variable", "type"), (_ej_s(wvar),
			_ej_s(wtype == "aweight" ? "analytic" : (wtype == "fweight" ? "frequency" : (wtype == "pweight" ? "probability" : wtype)))))),
		 _ej_sa(absvars), _ej_sa(clusters), sample,
		 _ej_o(("drop_singletons"), (_ej_b(_est_sc("e(drop_singletons)"))))))

	structures = _ej_o(("vcov", "fixed_effects", "numerics"),
		("[" + vcov + "]", "[" + invtokens(fe, ", ") + "]",
		 _ej_o(("kind", "iterative", "iterations", "converged"),
			(_ej_s("object"), "true", _est_num("ic"), _ej_b(_est_sc("e(converged)"))))))

	software = (
		_ej_o(("name", "version", "purl", "role", "source"), (_ej_s("reghdfe"), _ej_s(ver_reghdfe), _ej_s("pkg:generic/reghdfe@" + ver_reghdfe), _ej_s("estimator"), _ej_s("SSC"))),
		_ej_o(("name", "version", "purl", "role", "attributes"), (_ej_s("stata"), _ej_s(strofreal(c("stata_version"))),
			_ej_s("pkg:generic/stata@" + strofreal(c("stata_version"))), _ej_s("language"),
			_ej_o(("edition", "born_date", "processors"), (_ej_s(c("edition_real")), _ej_s(c("born_date")), _ej_n(c("processors")))))),
		_ej_o(("name", "version", "purl", "role", "source"), (_ej_s("ftools"), _ej_s(ver_ftools), _ej_s("pkg:generic/ftools@" + ver_ftools), _ej_s("dependency"), _ej_s("SSC"))))
	datain = _ej_o(("role", "location", "rows", "columns", "checksum"),
		(_ej_s("estimation"), (ident & c("filename") != "" ? _ej_s(c("filename")) : ""), _ej_n(rows_input), _ej_n(nvars),
		 (datasig != "" ? _ej_o(("algorithm", "value", "of", "method"), (_ej_s("datasignature"), _ej_s(datasig), _ej_s("in-memory"), _ej_s("Stata datasignature (rows, columns, names, contents)"))) : "")))
	provenance = _ej_o(("software", "environment", "data", "agent"),
		("[" + invtokens(software, ", ") + "]",
		 _ej_o(("os", "machine", "random"), (_ej_s(c("os")), _ej_s(c("machine_type")), _ej_o("rngtype", _ej_s(c("rngtype"))))),
		 "[" + datain + "]",
		 (ident ? _ej_o(("user", "host"), (_ej_s(c("username")), _ej_s(c("hostname")))) : "")))

	messages = nsing > 0 ? "[" + _ej_o(("level", "code", "source", "message"), (_ej_s("info"), _ej_s("singletons"), _ej_s("reghdfe"), _ej_s(strofreal(nsing) + " singleton rows dropped"))) + "]" : ""
	meta = _ej_o(("id", "created", "status", "estimator", "responses", "profiles", "messages"),
		(_ej_s(_est_uuid()), _ej_s(created), _ej_s("ok"), _ej_o(("family", "method"), (_ej_s("linear"), _ej_s("ols"))),
		 _ej_sa(st_global("e(depvar)")), _ej_sa(("inference/0.1", "linear-fe/0.1")), messages))
	sections = ("meta", "specification", "metrics", "parameters", "structures", "provenance")
	history = "[" + _ej_o(("when", "by", "action", "sections"), (_ej_s(created),
		_ej_o(("name", "version"), (_ej_s("estimation_write"), _ej_s("0.1.0"))), _ej_s("created"), _ej_sa(sections))) + "]"

	nl = char(10)
	rec = "{" + nl +
		" " + _ej_s("schema") + ": " + _ej_s("estimation/0.1") + "," + nl +
		" " + _ej_s("meta") + ": " + meta + "," + nl +
		" " + _ej_s("specification") + ": " + spec + "," + nl +
		" " + _ej_s("metrics") + ": " + metrics + "," + nl +
		" " + _ej_s("parameters") + ": [" + nl + "  " + invtokens(params, "," + nl + "  ") + nl + " ]," + nl +
		" " + _ej_s("structures") + ": " + structures + "," + nl +
		" " + _ej_s("provenance") + ": " + provenance + "," + nl +
		" " + _ej_s("history") + ": " + history + nl + "}" + nl

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

end
