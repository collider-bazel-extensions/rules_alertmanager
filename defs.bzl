"""Public API for rules_alertmanager.

Config (build time):
  alertmanager_config        — alertmanager.yml + templates, checked by
                               `amtool check-config` on every build.
  alertmanager_routes_test   — asserts which receivers label sets route to.

Hermetic server (test-time):
  alertmanager_server        — long-running alertmanager; writes
                               $TEST_TMPDIR/<name>.env when /-/ready.
  alertmanager_health_check  — pairs with alertmanager_server for
                               itest_service compositions.
  alertmanager_test          — sh_test macro: auto-launched server plus a
                               webhook sink that records notifications.

Cluster install (kind / production):
  alertmanager_install              — applies the pinned Helm chart
                                      (optionally with your config).
  alertmanager_install_health_check — paired readiness probe.
"""

load("//private:config.bzl",
     _alertmanager_config = "alertmanager_config",
     _alertmanager_routes_test = "alertmanager_routes_test")
load("//private:install.bzl",
     _alertmanager_install = "alertmanager_install",
     _alertmanager_install_health_check = "alertmanager_install_health_check")
load("//private:providers.bzl",
     _AlertmanagerBinaryInfo = "AlertmanagerBinaryInfo",
     _AlertmanagerConfigInfo = "AlertmanagerConfigInfo")
load("//private:server.bzl",
     _AlertmanagerServerInfo = "AlertmanagerServerInfo",
     _alertmanager_health_check = "alertmanager_health_check",
     _alertmanager_server = "alertmanager_server")
load("//private:test.bzl", _alertmanager_test = "alertmanager_test")

alertmanager_config = _alertmanager_config
alertmanager_routes_test = _alertmanager_routes_test
alertmanager_server = _alertmanager_server
alertmanager_health_check = _alertmanager_health_check
alertmanager_test = _alertmanager_test
alertmanager_install = _alertmanager_install
alertmanager_install_health_check = _alertmanager_install_health_check

AlertmanagerBinaryInfo = _AlertmanagerBinaryInfo
AlertmanagerConfigInfo = _AlertmanagerConfigInfo
AlertmanagerServerInfo = _AlertmanagerServerInfo
