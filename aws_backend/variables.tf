variable "extra_cors_origins" {
    description = "Zusätzliche CORS-Origins für lokale Entwicklung (z.B. http://192.168.122.164:8080)"
    type        = list(string)
    default     = []
}
