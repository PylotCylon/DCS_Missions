std = "lua51"

globals = {
  "_G",
  "trigger",
  "timer",
  "coalition",
  "Group",
  "Unit",
  "world",
  "env",
  "mist",
  "MESSAGE",
  "GROUP",
  "SET_GROUP",
  "BASE",
  "SCHEDULER",
  "UTILS"
}

read_globals = {
  "_VERSION"
}

files["scripts/**/*.lua"] = {
  std = "lua51"
}

exclude_files = {
  "**/vendor/**",
  "**/.venv/**"
}
