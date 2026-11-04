"""Analysis-time tests: the install macros (with and without a config)
and alertmanager_server instantiate correctly, without a cluster."""

load("@bazel_skylib//lib:unittest.bzl", "analysistest", "asserts")
load("@rules_alertmanager//:defs.bzl",
     "AlertmanagerServerInfo",
     "alertmanager_install",
     "alertmanager_install_health_check")

def _has_executable_impl(ctx):
    env = analysistest.begin(ctx)
    target = analysistest.target_under_test(env)
    asserts.true(
        env,
        target[DefaultInfo].files_to_run.executable != None,
        "expected target to expose an executable",
    )
    return analysistest.end(env)

_has_executable_test = analysistest.make(_has_executable_impl)

def _server_info_impl(ctx):
    env = analysistest.begin(ctx)
    target = analysistest.target_under_test(env)
    asserts.true(env, AlertmanagerServerInfo in target, "expected AlertmanagerServerInfo")
    info = target[AlertmanagerServerInfo]
    asserts.equals(env, "0.34.2", info.binary.version)
    asserts.equals(env, "alertmanager.yml", info.config.config.basename)
    return analysistest.end(env)

_server_info_test = analysistest.make(_server_info_impl)

def analysis_test_suite(name):
    alertmanager_install(name = name + "_install", tags = ["manual"])
    alertmanager_install(name = name + "_install_cfg", config = ":test_config", tags = ["manual"])
    alertmanager_install_health_check(name = name + "_health", tags = ["manual"])

    tests = []
    for subject in ["_install", "_install_cfg", "_health"]:
        _has_executable_test(
            name = name + subject + "_executable",
            target_under_test = ":" + name + subject,
        )
        tests.append(":" + name + subject + "_executable")
    _server_info_test(name = name + "_server_info", target_under_test = ":test_server")
    tests.append(":" + name + "_server_info")
    native.test_suite(name = name, tests = tests)
