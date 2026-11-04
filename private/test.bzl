"""alertmanager_test — sh_test macro with an auto-launched Alertmanager.

Each target gets its own alertmanager_server (unique env file, own
storage, no clustering) and, unless `webhook_sink = False`, a webhook
sink. Safe under `--jobs=N`.

The trampoline (alertmanager_test_trampoline.sh):
  1. starts the webhook sink and exports
       ALERTMANAGER_WEBHOOK_URL=http://127.0.0.1:<port>/
       ALERTMANAGER_WEBHOOK_DIR=<dir with one <n>.json per notification>
  2. starts the server (which expands ${ALERTMANAGER_WEBHOOK_URL} in the
     config), waits for its env file and sources it (ALERTMANAGER_URL,
     ALERTMANAGER_HOST, ALERTMANAGER_PORT, AMTOOL),
  3. exports ALERTMANAGER_TESTLIB (helpers: am_wait_notifications,
     am_post_alert) and execs the test with the target's args.
"""

load("@rules_shell//shell:sh_binary.bzl", "sh_binary")
load("@rules_shell//shell:sh_test.bzl", "sh_test")
load(":server.bzl", "alertmanager_server")

def alertmanager_test(
        name,
        srcs,
        config = None,
        webhook_sink = True,
        ready_timeout = 30,
        extra_args = None,
        deps = None,
        data = None,
        args = None,
        size = "medium",
        timeout = None,
        tags = None,
        **kwargs):
    """sh_test against an auto-launched Alertmanager.

    Args:
      name: target name.
      srcs: the test script (one file).
      config: an alertmanager_config. Default: with webhook_sink, every
        alert goes to the sink with group_wait 0s / group_interval 1s;
        without, the server's default (one receiver, no notifiers).
      webhook_sink: start a webhook sink and export
        ALERTMANAGER_WEBHOOK_URL / ALERTMANAGER_WEBHOOK_DIR. Default True.
      ready_timeout: seconds to wait for the server's /-/ready.
      extra_args: extra alertmanager flags.
      deps: forwarded to the inner sh_binary.
      data: forwarded to the inner sh_binary.
      args: arguments for the test script.
      size: sh_test size. Default "medium".
      timeout: sh_test timeout.
      tags: tags for the sh_test (the helper targets also get "manual").
      **kwargs: forwarded to sh_test (env, env_inherit, flaky, ...).
    """
    tags = tags or []
    if config == None:
        config = Label("//private:default_test_config") if webhook_sink else Label("//private:default_config")

    server_name = name + "_alertmanager"
    alertmanager_server(
        name = server_name,
        config = config,
        ready_timeout = str(ready_timeout),
        extra_args = extra_args or [],
        tags = tags + ["manual"],
        testonly = True,
    )

    inner_name = name + "_inner"
    sh_binary(
        name = inner_name,
        srcs = srcs,
        deps = deps,
        data = data,
        tags = tags + ["manual"],
        testonly = True,
    )

    sh_test(
        name = name,
        srcs = [Label("//private:alertmanager_test_trampoline.sh")],
        args = [
            "$(rootpath :{})".format(server_name),
            "$(rootpath :{})".format(inner_name),
            server_name,
            "$(rootpath {})".format(Label("//private:webhook_sink.py")) if webhook_sink else "-",
            "$(rootpath {})".format(Label("//private:testlib.sh")),
        ] + (args or []),
        data = [
            ":" + server_name,
            ":" + inner_name,
            Label("//private:webhook_sink.py"),
            Label("//private:testlib.sh"),
        ],
        size = size,
        timeout = timeout,
        tags = tags,
        **kwargs
    )
