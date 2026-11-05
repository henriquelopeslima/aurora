resource "google_monitoring_notification_channel" "email" {
  display_name = "aurora - e-mail do dono"
  type         = "email"
  labels = {
    email_address = var.alert_email
  }

  depends_on = [google_project_service.apis]
}

# Testa o caminho inteiro que o usuário usa: DNS, Cloudflare, tunnel, nginx e php.
resource "google_monitoring_uptime_check_config" "app" {
  display_name = "aurora - ${var.domain}"
  period       = "300s"
  timeout      = "10s"

  http_check {
    path         = "/"
    port         = 443
    use_ssl      = true
    validate_ssl = true
  }

  monitored_resource {
    type = "uptime_url"
    labels = {
      project_id = var.project_id
      host       = var.domain
    }
  }

  depends_on = [google_project_service.apis]
}

resource "google_monitoring_alert_policy" "app_down" {
  display_name = "aurora fora do ar"
  combiner     = "OR"

  conditions {
    display_name = "uptime check falhando"
    condition_threshold {
      filter          = "metric.type=\"monitoring.googleapis.com/uptime_check/check_passed\" AND resource.type=\"uptime_url\" AND metric.label.check_id=\"${google_monitoring_uptime_check_config.app.uptime_check_id}\""
      comparison      = "COMPARISON_GT"
      threshold_value = 1
      duration        = "600s"

      aggregations {
        alignment_period     = "300s"
        per_series_aligner   = "ALIGN_NEXT_OLDER"
        cross_series_reducer = "REDUCE_COUNT_FALSE"
        group_by_fields      = ["resource.label.host"]
      }

      trigger {
        count = 1
      }
    }
  }

  notification_channels = [google_monitoring_notification_channel.email.name]

  documentation {
    content = "https://${var.domain} falhou no uptime check por 10 min. Diagnóstico: `tofu output ssh_command`, depois `sudo docker compose -p aurora ps`."
  }
}
