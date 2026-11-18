using AdminPortal.Models;
using AdminPortal.Services;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using System.Security.Claims;

namespace AdminPortal.Controllers;

/// Figma web: "Profile" (Edit Profile) and "Notification Settings".
[Authorize(Policy = "Admin")]
public class ProfileController(SupabaseClient db) : Controller
{
    private string Me => User.FindFirstValue(ClaimTypes.NameIdentifier)!;

    [HttpGet]
    public async Task<IActionResult> Index()
    {
        ViewData["Active"] = "Profile";
        var a = await db.GetOneAsync<AdminRow>($"event_administrators?select=*&event_admin_id=eq.{Me}");
        if (a is null) return RedirectToAction("Login", "Account");
        return View(new ProfileVm
        {
            Name = a.Name, Email = a.Email, StaffNumber = a.StaffNumber, Department = a.Department, Phone = a.Phone,
        });
    }

    [HttpPost, ValidateAntiForgeryToken]
    public async Task<IActionResult> Index(ProfileVm vm)
    {
        ViewData["Active"] = "Profile";
        if (!ModelState.IsValid) return View(vm);
        try
        {
            await db.UpdateAsync($"event_administrators?event_admin_id=eq.{Me}", new
            {
                name = vm.Name.Trim(),
                staff_number = string.IsNullOrWhiteSpace(vm.StaffNumber) ? null : vm.StaffNumber.Trim(),
                department = vm.Department,
                phone = string.IsNullOrWhiteSpace(vm.Phone) ? null : vm.Phone.Trim(),
            });
            TempData["Success"] = "Profile saved.";
            return RedirectToAction(nameof(Index));
        }
        catch (SupabaseException ex)
        {
            ModelState.AddModelError("", ex.Message);
            return View(vm);
        }
    }

    [HttpGet]
    public async Task<IActionResult> Notifications()
    {
        ViewData["Active"] = "Settings";
        var prefs = await db.GetOneAsync<NotificationPrefs>($"admin_notification_prefs?select=*&event_admin_id=eq.{Me}");
        return View(prefs ?? new NotificationPrefs());
    }

    [HttpPost, ValidateAntiForgeryToken]
    public async Task<IActionResult> Notifications(NotificationPrefs prefs)
    {
        try
        {
            await db.UpdateAsync($"admin_notification_prefs?event_admin_id=eq.{Me}", prefs);
            TempData["Success"] = "Preferences saved.";
        }
        catch (SupabaseException ex) { TempData["Error"] = ex.Message; }
        return RedirectToAction(nameof(Notifications));
    }
}
