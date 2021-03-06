test_that('Characters raise error', {
  mod <- list()
  mod[[1]] <- lm(hp ~ mpg, mtcars)
  mod[[2]] <- 'ljaksdf'
  expect_error(modelsummary(mod))
  expect_error(modelsummary(mod[[2]]))
})

test_that('Numerics raise error', {
  mod <- list()
  mod[[1]] <- lm(hp ~ mpg, mtcars)
  mod[[2]] <- 1:30
  expect_error(modelsummary(mod))
  expect_error(modelsummary(mod[[2]]))
})

test_that('NULL raises error', {
  mod <- lm(hp ~ mpg, mtcars)
  mod <- list(mod, NULL)
  expect_error(modelsummary(mod))
  expect_error(modelsummary(mod[[2]]))
})
