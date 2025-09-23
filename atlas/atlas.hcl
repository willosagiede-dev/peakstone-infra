env "dev" {
  url = "env://ATLAS_DEV_URL"
  dev = url
  migration {
    dir = "file://migrations"
  }
  lint {
    destructive = "prompt"
  }
}

env "staging" {
  url = "env://ATLAS_STAGING_URL"
  migration { dir = "file://migrations" }
}

env "prod" {
  url = "env://ATLAS_PROD_URL"
  migration { dir = "file://migrations" }
}
