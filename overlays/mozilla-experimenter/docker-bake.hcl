group "default" {
  targets = ["megazords", "schemas", "cirrus", "experimenter-test"]
}

group "ci-test" {
  targets = ["megazords", "schemas", "cirrus", "experimenter-test"]
}

target "megazords" {
  context    = "application-services"
  dockerfile = "Dockerfile"
  tags       = ["experimenter:megazords"]
}

target "schemas" {
  context    = "schemas"
  dockerfile = "Dockerfile"
  target     = "dev"
  tags       = ["schemas:dev"]
}

target "cirrus" {
  context    = "cirrus/server"
  dockerfile = "Dockerfile"
  target     = "deploy"
  tags       = ["cirrus:deploy"]

  contexts = {
    "experimenter:megazords" = "target:megazords"
    fml                       = "experimenter/experimenter/features/manifests"
  }
}

target "experimenter-test" {
  context    = "experimenter"
  dockerfile = "Dockerfile"
  target     = "test"
  tags       = ["experimenter:test"]

  contexts = {
    "experimenter:megazords" = "target:megazords"
  }
}
