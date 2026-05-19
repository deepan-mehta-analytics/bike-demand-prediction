# tests/testthat/helper-workdir.R
# Sourced by test_dir() before each test file.
# Sets the working directory to shiny_app/ so that source("*.R") calls in
# test files resolve to the correct Shiny module files.
repo_root <- rprojroot::find_root(rprojroot::is_git_root)      # walk up to .git boundary
setwd(file.path(repo_root, "shiny_app"))                       # absolute path — safe from any starting directory
