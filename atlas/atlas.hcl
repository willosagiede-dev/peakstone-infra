env "dev" {
  url = "env://ATLAS_DEV_URL"
  dev = url
  migration {
    dir = "file://atlas/migrations"
  }
  lint {
    destructive = "prompt"
  }
}

env "staging" {
  url = "env://ATLAS_STAGING_URL"
  migration { dir = "file://atlas/migrations" }
}

env "prod" {
  url = "env://ATLAS_PROD_URL"
  migration { dir = "file://atlas/migrations" }
}
