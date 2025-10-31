ExUnit.start()

# Exclude external API tests by default to avoid hitting public services
# Run with: mix test --include external_api (to include them)
ExUnit.configure(exclude: [:external_api])
