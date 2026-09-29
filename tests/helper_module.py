"""Loads bin/omasnapper-helper, which has no .py suffix, as a module."""

import importlib.machinery
import importlib.util
import os

HELPER = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "bin", "omasnapper-helper")


def load_helper():
    loader = importlib.machinery.SourceFileLoader("omasnapper_helper", HELPER)
    spec = importlib.util.spec_from_loader("omasnapper_helper", loader)
    module = importlib.util.module_from_spec(spec)
    loader.exec_module(module)
    return module
