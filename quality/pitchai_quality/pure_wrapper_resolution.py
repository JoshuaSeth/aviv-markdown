# Copyright (c) 2026 PitchAI. All rights reserved.
"""Resolve whether a call forwards parameters to a repository-local target."""

from __future__ import annotations

import ast
from dataclasses import dataclass
from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from pitchai_quality.pure_wrapper_index import CallableIndex

_MIN_DOTTED_PARTS = 2


@dataclass(frozen=True)
class _ParameterSet:
    regular: frozenset[str]
    vararg: str | None
    kwarg: str | None


@dataclass(frozen=True)
class FunctionScope:
    """Module and optional class containing one function."""

    module: str
    class_name: str | None


def _parameters(node: ast.FunctionDef | ast.AsyncFunctionDef) -> _ParameterSet:
    regular_arguments = (*node.args.posonlyargs, *node.args.args, *node.args.kwonlyargs)
    regular_names = (argument.arg for argument in regular_arguments)
    return _ParameterSet(
        regular=frozenset(regular_names),
        vararg=node.args.vararg.arg if node.args.vararg is not None else None,
        kwarg=node.args.kwarg.arg if node.args.kwarg is not None else None,
    )


def _name_is_parameter(name: str, parameters: _ParameterSet) -> bool:
    return name in parameters.regular or name in {parameters.vararg, parameters.kwarg}


def _argument_is_parameter(argument: ast.AST, parameters: _ParameterSet) -> bool:
    if isinstance(argument, ast.Name):
        return _name_is_parameter(argument.id, parameters)
    if isinstance(argument, ast.Starred) and isinstance(argument.value, ast.Name):
        return argument.value.id == parameters.vararg
    return False


def _keyword_value_is_parameter(keyword: ast.keyword, parameters: _ParameterSet) -> bool:
    if keyword.arg is None and isinstance(keyword.value, ast.Name):
        return keyword.value.id == parameters.kwarg
    return isinstance(keyword.value, ast.Name) and _name_is_parameter(keyword.value.id, parameters)


def _call_uses_only_parameters(call: ast.Call, parameters: _ParameterSet) -> bool:
    return all(_argument_is_parameter(argument, parameters) for argument in call.args) and all(
        _keyword_value_is_parameter(keyword, parameters) for keyword in call.keywords
    )


def _resolve_bound_name(name: str, *, index: CallableIndex, bindings: dict[str, str]) -> str | None:
    bound = bindings.get(name)
    if bound is None:
        return None
    return index.resolve(bound)


def _attribute_dotted_name(node: ast.AST) -> str | None:
    if isinstance(node, ast.Name):
        return node.id
    if isinstance(node, ast.Attribute):
        parent = _attribute_dotted_name(node.value)
        return f"{parent}.{node.attr}" if parent else None
    return None


def _resolve_dotted_name(dotted: str, *, index: CallableIndex, bindings: dict[str, str]) -> str | None:
    parts = dotted.split(".")
    for split_at in range(len(parts) - 1, 0, -1):
        prefix = ".".join(parts[:split_at])
        suffix = ".".join(parts[split_at:])
        bound_prefix = bindings.get(prefix, prefix)
        resolved = index.resolve(f"{bound_prefix}.{suffix}")
        if resolved is not None:
            return resolved
    return index.resolve(dotted)


def _resolve_same_class_receiver(
    dotted: str,
    *,
    scope: FunctionScope,
    parameters: _ParameterSet,
    index: CallableIndex,
) -> str | None:
    if scope.class_name is None:
        return None
    parts = dotted.split(".")
    if len(parts) < _MIN_DOTTED_PARTS:
        return None
    receiver = parts[0]
    method = parts[-1]
    if receiver in parameters.regular or receiver in {scope.class_name, "cls"}:
        return index.resolve(f"{scope.module}.{scope.class_name}.{method}")
    return None


def _resolve_attribute_target(
    node: ast.Attribute,
    *,
    scope: FunctionScope,
    parameters: _ParameterSet,
    index: CallableIndex,
    bindings: dict[str, str],
) -> str | None:
    dotted = _attribute_dotted_name(node)
    if dotted is None:
        return None
    receiver_target = _resolve_same_class_receiver(dotted, scope=scope, parameters=parameters, index=index)
    return receiver_target or _resolve_dotted_name(dotted, index=index, bindings=bindings)


def resolve_parameter_call_target(
    call: ast.Call,
    node: ast.FunctionDef | ast.AsyncFunctionDef,
    scope: FunctionScope,
    index: CallableIndex,
    bindings: dict[str, str],
) -> str | None:
    """Resolve a local call only when every argument forwards a parameter.

    Returns:
        The repository-qualified target, when the call is a pure forwarding call.
    """
    parameters = _parameters(node)
    if not _call_uses_only_parameters(call, parameters):
        return None
    if isinstance(call.func, ast.Name):
        same_module = f"{scope.module}.{call.func.id}"
        return index.resolve(same_module) or _resolve_bound_name(call.func.id, index=index, bindings=bindings)
    if isinstance(call.func, ast.Attribute):
        return _resolve_attribute_target(
            call.func,
            scope=scope,
            parameters=parameters,
            index=index,
            bindings=bindings,
        )
    return None
