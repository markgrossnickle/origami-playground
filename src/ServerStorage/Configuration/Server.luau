-- Server-only API config. Lives in ServerStorage so it is NEVER replicated to
-- clients (ReplicatedStorage is). Only server-side Knit services require this.
return {
	API_URL = "https://origami-server.fly.dev",
	API_KEY = "c8bee2ff3b9211e5c9a0d272d722276fa961a823a0effe86078f2ba718dfcfba",
}
