using AdminPortal.Models;
using AdminPortal.Services;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace AdminPortal.Controllers;

/// Admin "Redemptions" page: monitor coupon use (read-only).
/// Approving / rejecting is done by Cafeteria Staff in CafeteriaController.
[Authorize(Policy = "AdminOrCafeteria")]
public class RedemptionsController(SupabaseClient db) : Controller
{
    public async Task<IActionResult> Index()
    {
        // Cafeteria staff have their own pages (Current Redemptions / History)
        if (User.IsInRole("cafeteria")) return RedirectToAction("Index", "Cafeteria");

        ViewData["Active"] = "Redemptions";
        try
        {
            var rows = await db.RpcAsync<List<RedemptionRecord>>("list_redemptions", new { p_limit = 50 });
            return View(rows);
        }
        catch (SupabaseException ex) { TempData["Error"] = ex.Message; return View(new List<RedemptionRecord>()); }
    }
}
