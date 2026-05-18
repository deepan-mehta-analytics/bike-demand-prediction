# Load the test framework for discovering and running all test files.
library(testthat)

# Set working directory to shiny_app so all source() and file path calls resolve correctly.
setwd("shiny_app")

# Discover and run all test-*.R files in the tests/testthat directory.
testthat::test_dir(
  "../tests/testthat",                                 # directory containing test files
  reporter  = "progress",                              # show each test as it runs
  stop_on_failure = TRUE                               # exit non-zero on first failure
)
