// kOS's addon list can lack KALS with the addon loaded (sock_probe.ks: ADDONS lists
// AGX ASTROGATOR CAMERA KAC KE MJ RT TR), though KSP loaded KalsCoproc.dll and the type carries [kOSAddon("KALS")]. kOS's
// assembly walk drops a type that fails to load without a word (ReflectUtil.GetLoadedTypes keeps the types that did).
// So, at KSP's start: log whether this assembly's types load under KSP's runtime (and why not, if not), and register
// KALS with kOS ourselves (AddonManager.RegisterMethod, the walk's own registration; a second registration of the same
// attribute only overwrites it). Every line in KSP.log starts with [KalsCoproc]. Plus the assembly tags StockCamera has.
using System;
using System.Reflection;
using UnityEngine;

[assembly: KSPAssembly("KalsCoproc", 1, 0)]
[assembly: KSPAssemblyDependency("kOS", 0, 0)]

namespace KalsCoproc
{
    [KSPAddon(KSPAddon.Startup.Instantly, true)]
    public class KalsDiag : MonoBehaviour
    {
        void Awake()
        {
            try
            {
                try
                {
                    Type[] ts = typeof(KalsDiag).Assembly.GetTypes();
                    Debug.Log("[KalsCoproc] " + ts.Length + " types load");
                }
                catch (ReflectionTypeLoadException ex)
                {
                    foreach (var le in ex.LoaderExceptions) Debug.LogError("[KalsCoproc] type load: " + le);
                }
                Type t = null;
                try { t = typeof(KalsAddon); Debug.Log("[KalsCoproc] KalsAddon type ok: " + t.FullName); }
                catch (Exception ex) { Debug.LogError("[KalsCoproc] KalsAddon type failed: " + ex); }
                if (t == null) return;
                MethodInfo m = typeof(kOS.AddOns.AddonManager).GetMethod("RegisterMethod",
                    BindingFlags.Static | BindingFlags.Public | BindingFlags.NonPublic);
                if (m == null) { Debug.LogError("[KalsCoproc] kOS has no AddonManager.RegisterMethod"); return; }
                m.Invoke(null, new object[] { new kOS.AddOns.kOSAddonAttribute("KALS"), t });
                Debug.Log("[KalsCoproc] registered KALS with kOS");
            }
            catch (Exception ex) { Debug.LogError("[KalsCoproc] diag: " + ex); }
        }
    }
}
