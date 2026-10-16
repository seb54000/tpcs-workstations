from ansible.errors import AnsibleFilterError


def pinned_packages(names, versions):
    """Fail closed for an unrecorded direct package in the enabled baseline."""
    single = isinstance(names, str)
    result = []
    for name in [names] if single else names:
        version = versions.get(name, versions.get(name + ":amd64"))
        if version is None:
            raise AnsibleFilterError("Package absent from TPCS baseline: " + name)
        result.append(name + "=" + version)
    return result[0] if single else result


class FilterModule:
    def filters(self):
        return {"tpcs_pinned_packages": pinned_packages}
