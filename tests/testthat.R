# tests/testthat.R
# Run from repo root: Rscript tests/testthat.R
# Or from shiny_app/: Rscript -e 'testthat::test_dir("../tests/testthat")'
library(testthat)                                                    # load test framework

# ── Working directory setup ───────────────────────────────────────────────────
repo_root <- rprojroot::find_root(rprojroot::is_git_root)           # walk up to .git boundary regardless of invocation directory
setwd(file.path(repo_root, "shiny_app"))                            # absolute path — safe from any starting directory

# ── Guard: testthat::test_dir() errors on an empty directory ─────────────────
test_dir_path <- file.path(repo_root, "tests", "testthat")          # absolute path to test directory
test_files    <- list.files(test_dir_path, pattern = "^test-.*\\.R$") # find all test-*.R files
if (length(test_files) == 0L) {                                      # no test files yet
  message("[ FAIL 0 | WARN 0 | SKIP 0 | PASS 0 ] (no test files found)")
  quit(status = 0L)                                                  # exit cleanly — nothing to run
}

# ── Run testthat suite ────────────────────────────────────────────────────────
stop_on_fail <- !nzchar(Sys.getenv("CI"))                           # TRUE locally (fast fail); FALSE in CI (show all failures)
testthat::test_dir(                                                  # discover and run all test-*.R files
  test_dir_path,                                                     # absolute path resolved above
  reporter        = "progress",                                      # show each test as it runs
  stop_on_failure = stop_on_fail                                     # environment-aware: fail fast locally, report all in CI
)
