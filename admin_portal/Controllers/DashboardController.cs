using AdminPortal.Models;
using AdminPortal.Services;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace AdminPortal.Controllers;

/// Figma web: "Welcome Admin" - Good day, Admin + 3 stat cards + Recent Activity.
[Authorize]
public class DashboardController(SupabaseClient db) : Controller
{
    public async Task<IActionResult> Index()
    {
        if (User.IsInRole("cafeteria")) return RedirectToAction("Index", "Cafeteria");
        if (!User.IsInRole("admin")) return RedirectToAction("Login", "Account");

        ViewData["Active"] = "Dashboard";
        try
        {
            var stats = (await db.RpcAsync<List<DashboardStats>>("admin_dashboard_stats")).FirstOrDefault() ?? new();
            var activity = await db.GetAsync<ActivityRow>("audit_log?select=title,detail,created_at&order=created_at.desc&limit=5");
            return View((stats, activity));
        }
        catch (SupabaseException ex)
        {
            TempData["Error"] = ex.Message;
            return View((new DashboardStats(), new List<ActivityRow>()));
        }
    }

    [AllowAnonymous]
    public IActionResult Error() => View();
}
