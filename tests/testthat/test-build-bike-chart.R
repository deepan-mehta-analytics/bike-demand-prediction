library(testthat)                                                               # testing framework
library(withr)                                                                  # env-var isolation without leaking state
library(rprojroot)                                                              # portable project root detection

proj_root <- find_root(has_file("renv.lock"))                                   # walk up to repo root (renv.lock is the anchor)
setwd(file.path(proj_root, "shiny_app"))                                        # server_helpers.R lives in shiny_app/

source("server_helpers.R")                                                      # provides build_engine_subtitle_line() (added in C1)

# ── C1: build_engine_subtitle_line ──────────────────────────────────────────

test_that("build_engine_subtitle_line returns FastAPI label when USE_FASTAPI=true", {
  with_envvar(c(USE_FASTAPI = "true"), {                                        # isolate env var to this block only
    out <- build_engine_subtitle_line()                                         # call helper under FastAPI condition
    expect_equal(out, "Engine: FastAPI Random Forest")                          # exact string expected by the UI
  })
})

test_that("build_engine_subtitle_line returns local label when USE_FASTAPI=false", {
  with_envvar(c(USE_FASTAPI = "false"), {                                       # explicit false → local model path
    out <- build_engine_subtitle_line()                                         # call helper under local condition
    expect_equal(out, "Engine: Local linear regression")                        # exact string expected by the UI
  })
})

test_that("build_engine_subtitle_line returns local label when USE_FASTAPI unset", {
  with_envvar(c(USE_FASTAPI = NA), {                                            # NA in with_envvar unsets the variable
    out <- build_engine_subtitle_line()                                         # call helper with env var absent
    expect_equal(out, "Engine: Local linear regression")                        # absent var → default local path
  })
})

test_that("build_engine_subtitle_line returns local label when USE_FASTAPI has unexpected value", {
  with_envvar(c(USE_FASTAPI = "yes"), {                                         # "yes" is not exactly "true" → local
    out <- build_engine_subtitle_line()                                         # call helper with unrecognised value
    expect_equal(out, "Engine: Local linear regression")                        # anything not exactly "true" → local
  })
})
