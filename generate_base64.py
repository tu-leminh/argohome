import os
import yaml
import base64

key = "6575eaaa99e155fdde15b0ed038f3a0ca04c908cc77c2446c16495ce18cede12"
domains = set(["lmtlmt", "nextcloud.lmtlmt", "qbittorrent.lmtlmt"])

def find_myaddr_hosts(d):
    if isinstance(d, dict):
        if 'myaddr' in d and isinstance(d['myaddr'], dict) and 'host' in d['myaddr']:
            host = d['myaddr']['host']
            if host.endswith('.myaddr.io'):
                domains.add(host.replace('.myaddr.io', ''))
        for v in d.values():
            find_myaddr_hosts(v)
    elif isinstance(d, list):
        for v in d:
            find_myaddr_hosts(v)

for root, _, files in os.walk("apps"):
    for file in files:
        if file == "values.yaml":
            with open(os.path.join(root, file)) as f:
                try:
                    data = yaml.safe_load(f)
                    find_myaddr_hosts(data)
                except Exception as e:
                    pass

# Also check homepage links
try:
    with open("apps/core/homepage/values.yaml") as f:
        data = yaml.safe_load(f)
        for group in data.get('config', {}).get('services', []):
            for service_group in group.values():
                for service in service_group:
                    for app_name, app_config in service.items():
                        if 'href' in app_config and 'myaddr.io' in app_config['href']:
                            host = app_config['href'].split('//')[1].split('/')[0]
                            if host.endswith('.myaddr.io'):
                                domains.add(host.replace('.myaddr.io', ''))
except:
    pass

mapping = ",".join([f"{d}:{key}" for d in sorted(list(domains))])
print(f"Subdomains found: {', '.join(sorted(list(domains)))}")
print(f"\nBase64:\n{base64.b64encode(mapping.encode()).decode()}")
