{{/*
One Homepage tile per pool disk (.Values.disks), matched by serial since
device names can change between boots. Short / Long: power-on time since the
newest completed SMART self-test of that type (smartd runs them, the nix
flake's smart-selftest-metrics timer exports them). Failed: how many of those
two failed.
*/}}
{{- define "homepage.diskTiles" -}}
{{- range .Values.disks }}
- {{ .name | quote }}:
    icon: https://raw.githubusercontent.com/walkxcode/dashboard-icons/main/png/scrutiny.png
    href: https://grafana.epricesx.duckdns.org/d/bcachefs
    description: {{ .description | quote }}
    widget:
      type: prometheusmetric
      url: http://vmsingle-vm.infra.svc:8428
      refreshInterval: 300000
      metrics:
        - label: Short test
          query: max(smart_selftest_last_age_seconds{serial_number="{{ .serial }}",type="short"})
          format: { type: duration }
        - label: Long test
          query: max(smart_selftest_last_age_seconds{serial_number="{{ .serial }}",type="long"})
          format: { type: duration }
        - label: Failed
          query: sum(smart_selftest_last_failed{serial_number="{{ .serial }}"}) or vector(0)
          format: { type: number }
        - label: Temp
          query: max(smartctl_device_temperature{temperature_type="current"} * on(device) group_left smartctl_device{serial_number="{{ .serial }}"})
          format: { type: number, suffix: "°C" }
{{- end }}
{{- end }}
