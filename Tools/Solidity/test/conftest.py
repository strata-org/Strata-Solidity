# Copyright Strata Contributors
#
#  SPDX-License-Identifier: Apache-2.0 OR MIT

"""pytest configuration for the Tools/Solidity characterization tests.

The tests skip themselves when the `strataSolidity` binary or solc is
missing, which is convenient locally. Under CI (the `CI` environment
variable is set, as on GitHub Actions) a skipped test fails the run
instead: a CI stage whose tests all skipped would otherwise pass while
checking nothing.
"""

import os

import pytest


def pytest_sessionfinish(session: pytest.Session, exitstatus: int) -> None:
    if not os.environ.get("CI") or exitstatus != pytest.ExitCode.OK:
        return
    reporter = session.config.pluginmanager.get_plugin("terminalreporter")
    skipped = len(reporter.stats.get("skipped", [])) if reporter else 0
    if skipped:
        if reporter:
            reporter.write_line(
                f"error: {skipped} test(s) skipped under CI; "
                "build strataSolidity and put solc and z3 on PATH",
                red=True,
            )
        session.exitstatus = pytest.ExitCode.TESTS_FAILED
