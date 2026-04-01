#!/usr/bin/env fish

# WARNING: This script removes ALL Flatpak applications, runtimes, and remotes
# from BOTH user and system installations — not just Lumoria. It also wipes
# /var/lib/flatpak with sudo. Only use this for a complete development reset.

echo "==> Removing all user-installed Flatpak apps"
for app in (flatpak list --app --columns=application --user)
    if test -n "$app"
        flatpak uninstall -y --user "$app"; or true
    end
end

echo "==> Removing all system-installed Flatpak apps"
for app in (flatpak list --app --columns=application --system)
    if test -n "$app"
        flatpak uninstall -y --system "$app"; or true
    end
end

echo "==> Removing leftover user runtimes"
for runtime in (flatpak list --runtime --columns=application --user)
    if test -n "$runtime"
        flatpak uninstall -y --user "$runtime"; or true
    end
end

echo "==> Removing leftover system runtimes"
for runtime in (flatpak list --runtime --columns=application --system)
    if test -n "$runtime"
        flatpak uninstall -y --system "$runtime"; or true
    end
end

echo "==> Removing all user remotes"
for remote in (flatpak remotes --user --columns=name)
    if test -n "$remote"
        flatpak remote-delete --user "$remote"; or true
    end
end

echo "==> Removing all system remotes"
for remote in (flatpak remotes --system --columns=name)
    if test -n "$remote"
        flatpak remote-delete --system "$remote"; or true
    end
end

echo "==> Removing leftover user Flatpak data"
rm -rf ~/.local/share/flatpak
rm -rf ~/.var/app

echo "==> Removing leftover system Flatpak data"
sudo rm -rf /var/lib/flatpak

echo "==> Recreating system Flatpak data dir"
sudo mkdir -p /var/lib/flatpak

echo "==> Re-adding Flathub"
flatpak remote-add  --user --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo

echo "==> Cleanup complete"
echo "Installed remotes now:"
flatpak remotes

rm -rf ~/.var/app/net.windower.Lumoria || true
rm -rf ~/Games/Lumoria || true
echo "==> Cleanup complete"
echo ""
echo "==> How to install Lumoria:"
echo "flatpak remote-add --if-not-exists --user flathub https://dl.flathub.org/repo/flathub.flatpakrepo"
echo "flatpak remote-add --if-not-exists --user lumoria https://lumoria.windower.net/repo/lumoria.flatpakrepo"
echo "flatpak install --user -y lumoria net.windower.Lumoria"
