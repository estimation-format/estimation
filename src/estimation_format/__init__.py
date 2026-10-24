# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Ted Matherly and the estimation-format contributors
"""Reference tools for the `estimation` format: write, read, validate and redact records.

    import estimation_format as ef
    rec = ef.new_record(parameters, estimator={"family": "linear", "method": "ols"})
    ef.write(rec, "model.estimation.json")
    issues = ef.validate(ef.read("model.estimation.json"))

The specification is spec/estimation.md in https://github.com/estimation-format/estimation.
"""

__version__ = "0.1.0.dev0"

from .records import (
    CORE,
    DEFAULT_IDENTIFYING,
    FAIL_BYTES,
    PACKAGED_SCHEMAS,
    SCHEMA,
    WARN_BYTES,
    WARN_ELEMENTS,
    EstimationError,
    Issue,
    Schemas,
    add_digest,
    attachment,
    attachment_path,
    canonical_json,
    check_digest,
    core_digest,
    count_elements,
    decode_nonfinite,
    identifying_paths,
    jsonschema_check,
    load_schemas,
    load_structure,
    loads,
    main,
    new_record,
    prepare,
    read,
    record_identifying_paths,
    redact,
    spill,
    to_json,
    validate,
    write,
)

__all__ = [
    "CORE",
    "DEFAULT_IDENTIFYING",
    "FAIL_BYTES",
    "PACKAGED_SCHEMAS",
    "SCHEMA",
    "WARN_BYTES",
    "WARN_ELEMENTS",
    "EstimationError",
    "Issue",
    "Schemas",
    "__version__",
    "add_digest",
    "attachment",
    "attachment_path",
    "canonical_json",
    "check_digest",
    "core_digest",
    "count_elements",
    "decode_nonfinite",
    "identifying_paths",
    "jsonschema_check",
    "load_schemas",
    "load_structure",
    "loads",
    "main",
    "new_record",
    "prepare",
    "read",
    "record_identifying_paths",
    "redact",
    "spill",
    "to_json",
    "validate",
    "write",
]
