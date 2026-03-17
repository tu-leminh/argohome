import os
import yaml
import glob

print(f"{'Application':<25} | {'DuckDNS':<10} | {'FreeMyIP':<10} | {'MyAddr':<10} | {'Tailscale':<10}")
print("-" * 75)

def find_ingress_targets(d):
    if isinstance(d, dict):
        if 'ingressTargets' in d:
            return d['ingressTargets']
        for k, v in d.items():
            res = find_ingress_targets(v)
            if res:
                return res
    return None

for val_file in sorted(glob.glob("apps/*/*/values.yaml")):
    app_dir = os.path.dirname(val_file)
    app_name = os.path.basename(app_dir)
    category = os.path.basename(os.path.dirname(app_dir))
    
    with open(val_file, 'r') as f:
        try:
            data = yaml.safe_load(f)
        except Exception:
            continue
            
    if not data:
        data = {}
        
    ingress_targets = find_ingress_targets(data)
        
    has_duckdns = False
    has_freemyip = False
    has_myaddr = False
        
    if ingress_targets:
        has_duckdns = 'duckdns' in ingress_targets
        has_freemyip = 'freemyip' in ingress_targets
        has_myaddr = 'myaddr' in ingress_targets
        
    has_tailscale = os.path.exists(os.path.join(app_dir, 'templates', 'ingress-tailscale.yaml'))
    has_ingressroute = os.path.exists(os.path.join(app_dir, 'templates', 'ingressroute.yaml'))
    
    if has_ingressroute or has_tailscale or category in ['media', 'core']:
        print(f"{category+'/'+app_name:<25} | {'YES' if has_duckdns else 'NO':<10} | {'YES' if has_freemyip else 'NO':<10} | {'YES' if has_myaddr else 'NO':<10} | {'YES' if has_tailscale else 'NO':<10}")

