using AdminPortal.Models;
using AdminPortal.Services;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace AdminPortal.Controllers;

/// "Meals" page - Cafeteria Staff only (SRS "Coupon Management").
/// Event Administrators no longer see or open this page.
/// Whatever is Available here appears in the student app's Coupons tab straight away.
/// Who may change what is enforced in the database (07_meals.sql).
[Authorize(Policy = "Cafeteria")]
public class CouponsController(SupabaseClient db) : Controller
{
    private bool IsCafeteria => User.IsInRole("cafeteria");

    /// Cafeteria staff only ever see and edit meals (Food).
    private string Noun => IsCafeteria ? "meal" : "coupon";

    public override void OnActionExecuting(Microsoft.AspNetCore.Mvc.Filters.ActionExecutingContext context)
    {
        ViewData["Active"] = "Coupons";
        ViewData["IsCafeteria"] = IsCafeteria;
        base.OnActionExecuting(context);
    }

    // ---------------------------------------------------------------- List
    public async Task<IActionResult> Index(string show = "All")
    {
        ViewData["Show"] = show;
        var q = "coupons?select=*,redemptions(count)&order=is_active.desc,valid_until.desc,title";
        if (IsCafeteria) q += "&category=eq.Food";
        try
        {
            var rows = await db.GetAsync<CouponRow>(q);
            rows = show switch
            {
                "Available" => rows.Where(c => c.IsActive && !c.IsExpired).ToList(),
                "Switched off" => rows.Where(c => !c.IsActive).ToList(),
                "Expired" => rows.Where(c => c.IsExpired).ToList(),
                _ => rows,
            };
            return View(rows);
        }
        catch (SupabaseException ex) { TempData["Error"] = ex.Message; return View(new List<CouponRow>()); }
    }

    // ---------------------------------------------------------------- Add
    [HttpGet]
    public IActionResult Create() => View("Form", new CouponFormVm
    {
        Category = "Food",
        ValidUntil = DateOnly.FromDateTime(DateTime.Today.AddMonths(3)),
    });

    [HttpPost, ValidateAntiForgeryToken]
    public async Task<IActionResult> Create(CouponFormVm vm)
    {
        if (IsCafeteria) vm.Category = "Food";
        if (!ModelState.IsValid) return View("Form", vm);
        try
        {
            var imageUrl = await UploadPhotoAsync(vm.Photo);
            var created = await db.InsertAsync<CouponRow>("coupons", Row(vm, imageUrl));
            TempData["Success"] = created.IsActive
                ? $"\"{created.Title}\" was added for {created.PointsCost} points. Students can redeem it now."
                : $"\"{created.Title}\" was saved but is switched off, so students cannot see it yet.";
            return RedirectToAction(nameof(Index));
        }
        catch (SupabaseException ex)
        {
            ModelState.AddModelError("", ex.Message);
            return View("Form", vm);
        }
    }

    // ---------------------------------------------------------------- Edit
    [HttpGet]
    public async Task<IActionResult> Edit(long id)
    {
        var c = await FindAsync(id);
        if (c is null) return NotFound();
        return View("Form", new CouponFormVm
        {
            CouponId = c.CouponId,
            Title = c.Title,
            Category = c.Category,
            PointsCost = c.PointsCost,
            ValidUntil = c.ValidUntil,
            Location = c.Location,
            Terms = c.Terms,
            IsActive = c.IsActive,
            ImageUrl = c.ImageUrl,
        });
    }

    [HttpPost, ValidateAntiForgeryToken]
    public async Task<IActionResult> Edit(long id, CouponFormVm vm)
    {
        vm.CouponId = id;
        if (IsCafeteria) vm.Category = "Food";
        if (!ModelState.IsValid) return View("Form", vm);
        try
        {
            var imageUrl = await UploadPhotoAsync(vm.Photo) ?? vm.ImageUrl;
            await db.UpdateAsync($"coupons?coupon_id=eq.{id}", Row(vm, imageUrl));
            TempData["Success"] = $"\"{vm.Title.Trim()}\" was updated.";
            return RedirectToAction(nameof(Index));
        }
        catch (SupabaseException ex)
        {
            ModelState.AddModelError("", ex.Message);
            return View("Form", vm);
        }
    }

    // ------------------------------------------------- Switch on / off
    /// Switched off = hidden from students (redemptions already made stay valid).
    [HttpPost, ValidateAntiForgeryToken]
    public async Task<IActionResult> Toggle(long id, bool active, string show = "All")
    {
        try
        {
            await db.UpdateAsync($"coupons?coupon_id=eq.{id}", new { is_active = active });
            TempData["Success"] = active
                ? $"The {Noun} is switched on. Students can see and redeem it."
                : $"The {Noun} is switched off. Students can no longer see it; codes already issued still work.";
        }
        catch (SupabaseException ex) { TempData["Error"] = ex.Message; }
        return RedirectToAction(nameof(Index), new { show });
    }

    // ---------------------------------------------------------------- Delete
    /// Only possible if nobody ever redeemed it (redemption records must be kept).
    [HttpPost, ValidateAntiForgeryToken]
    public async Task<IActionResult> Delete(long id)
    {
        try
        {
            await db.DeleteAsync($"coupons?coupon_id=eq.{id}");
            TempData["Success"] = $"The {Noun} was deleted.";
        }
        catch (SupabaseException ex) { TempData["Error"] = ex.Message; }
        return RedirectToAction(nameof(Index));
    }

    // ---------------------------------------------------------------- Helpers
    private async Task<CouponRow?> FindAsync(long id)
    {
        var q = $"coupons?select=*&coupon_id=eq.{id}";
        if (IsCafeteria) q += "&category=eq.Food";
        return await db.GetOneAsync<CouponRow>(q);
    }

    private static object Row(CouponFormVm vm, string? imageUrl) => new
    {
        title = vm.Title.Trim(),
        category = vm.Category,
        points_cost = vm.PointsCost,
        valid_until = vm.ValidUntil!.Value.ToString("yyyy-MM-dd"),
        location = vm.Location.Trim(),
        terms = (vm.Terms ?? "").Trim(),
        is_active = vm.IsActive,
        image_url = imageUrl,
    };

    private async Task<string?> UploadPhotoAsync(IFormFile? file)
    {
        if (file is null || file.Length == 0) return null;
        var ext = Path.GetExtension(file.FileName).ToLowerInvariant();
        if (ext is not (".jpg" or ".jpeg" or ".png" or ".webp"))
            throw new SupabaseException("Photo must be a .jpg, .png or .webp image.");
        await using var stream = file.OpenReadStream();
        // coupons/ folder: the only place cafeteria staff may upload (07_meals.sql)
        return await db.UploadPublicAsync("event-media", $"coupons/{Guid.NewGuid():N}{ext}", stream, file.ContentType);
    }
}