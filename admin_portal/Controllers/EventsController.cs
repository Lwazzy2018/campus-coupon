using AdminPortal.Models;
using AdminPortal.Services;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using System.Security.Claims;

namespace AdminPortal.Controllers;

/// Use cases: Create an event, Update event details, Publish event (FR-003, FR-004, FR-005, FR-023).
/// Figma web: "Create Event", "View Event".  Sequence Diagram 2, steps 9-16.
[Authorize(Policy = "Admin")]
public class EventsController(SupabaseClient db) : Controller
{
    public override void OnActionExecuting(Microsoft.AspNetCore.Mvc.Filters.ActionExecutingContext context)
    {
        ViewData["Active"] = "Event";
        base.OnActionExecuting(context);
    }

    // Event list (sidebar "Event")
    public async Task<IActionResult> Index(string? search)
    {
        var q = "events?select=*,rsvp(count)&order=event_date.desc";
        if (!string.IsNullOrWhiteSpace(search)) q += $"&title=ilike.*{Uri.EscapeDataString(search.Trim())}*";
        ViewData["Search"] = search;
        try { return View(await db.GetAsync<EventRow>(q)); }
        catch (SupabaseException ex) { TempData["Error"] = ex.Message; return View(new List<EventRow>()); }
    }

    // Steps 13-16: Open event details -> retrieve RSVP -> RSVP list (with attendance status)
    public async Task<IActionResult> Details(long id)
    {
        try
        {
            var ev = await db.GetOneAsync<EventRow>($"events?select=*,rsvp(count)&event_id=eq.{id}");
            if (ev is null) return NotFound();
            var people = await db.GetAsync<ParticipantRow>($"event_participants?select=*&event_id=eq.{id}&order=student_name");
            return View((ev, people));
        }
        catch (SupabaseException ex) { TempData["Error"] = ex.Message; return RedirectToAction(nameof(Index)); }
    }

    [HttpGet]
    public IActionResult Create() => View("Form", new EventFormVm { EventDate = DateOnly.FromDateTime(DateTime.Today.AddDays(7)) });

    // Steps 9-12: Create and publish event -> save event -> event saved -> show success message
    [HttpPost, ValidateAntiForgeryToken]
    public async Task<IActionResult> Create(EventFormVm vm)
    {
        if (!ModelState.IsValid) return View("Form", vm);
        try
        {
            var imageUrl = await UploadPosterAsync(vm.Poster);
            var created = await db.InsertAsync<EventRow>("events", new
            {
                admin_user_id = User.FindFirstValue(ClaimTypes.NameIdentifier),
                title = vm.Title.Trim(),
                description = vm.Description.Trim(),
                event_date = vm.EventDate!.Value.ToString("yyyy-MM-dd"),
                start_time = vm.StartTime!.Value.ToString("HH:mm"),
                end_time = vm.EndTime?.ToString("HH:mm"),
                location = vm.Location.Trim(),
                points_reward = vm.PointsReward,
                category = vm.Category,
                status = vm.Status,
                image_url = imageUrl,
            });
            TempData["Success"] = vm.Status == "published"
                ? $"\"{created.Title}\" was created and published. Students can now see it."
                : $"\"{created.Title}\" was saved as a draft.";
            return RedirectToAction(nameof(Details), new { id = created.EventId });
        }
        catch (SupabaseException ex)
        {
            ModelState.AddModelError("", ex.Message);
            return View("Form", vm);
        }
    }

    [HttpGet]
    public async Task<IActionResult> Edit(long id)
    {
        var ev = await db.GetOneAsync<EventRow>($"events?select=*&event_id=eq.{id}");
        if (ev is null) return NotFound();
        return View("Form", new EventFormVm
        {
            EventId = ev.EventId, Title = ev.Title, Description = ev.Description, EventDate = ev.EventDate,
            StartTime = ev.StartTime, EndTime = ev.EndTime, Location = ev.Location, PointsReward = ev.PointsReward,
            Category = ev.Category, Status = ev.Status, ImageUrl = ev.ImageUrl,
        });
    }

    [HttpPost, ValidateAntiForgeryToken]
    public async Task<IActionResult> Edit(long id, EventFormVm vm)
    {
        vm.EventId = id;
        if (!ModelState.IsValid) return View("Form", vm);
        try
        {
            var imageUrl = await UploadPosterAsync(vm.Poster) ?? vm.ImageUrl;
            await db.UpdateAsync($"events?event_id=eq.{id}", new
            {
                title = vm.Title.Trim(),
                description = vm.Description.Trim(),
                event_date = vm.EventDate!.Value.ToString("yyyy-MM-dd"),
                start_time = vm.StartTime!.Value.ToString("HH:mm"),
                end_time = vm.EndTime?.ToString("HH:mm"),
                location = vm.Location.Trim(),
                points_reward = vm.PointsReward,
                category = vm.Category,
                status = vm.Status,
                image_url = imageUrl,
            });
            TempData["Success"] = "Event updated.";
            return RedirectToAction(nameof(Details), new { id });
        }
        catch (SupabaseException ex)
        {
            ModelState.AddModelError("", ex.Message);
            return View("Form", vm);
        }
    }

    // "Delete Event": deletes if nobody RSVP'd, otherwise closes it (keeps attendance/reward history)
    [HttpPost, ValidateAntiForgeryToken]
    public async Task<IActionResult> Delete(long id)
    {
        try
        {
            var result = await db.RpcAsync<string>("delete_or_close_event", new { p_event_id = id });
            TempData["Success"] = result == "deleted"
                ? "Event deleted."
                : "Students had already RSVP'd, so the event was closed instead of deleted. Their records are kept.";
        }
        catch (SupabaseException ex) { TempData["Error"] = ex.Message; }
        return RedirectToAction(nameof(Index));
    }

    private async Task<string?> UploadPosterAsync(IFormFile? file)
    {
        if (file is null || file.Length == 0) return null;
        var ext = Path.GetExtension(file.FileName).ToLowerInvariant();
        if (ext is not (".jpg" or ".jpeg" or ".png" or ".webp"))
            throw new SupabaseException("Poster must be a .jpg, .png or .webp image.");
        await using var stream = file.OpenReadStream();
        return await db.UploadPublicAsync("event-media", $"events/{Guid.NewGuid():N}{ext}", stream, file.ContentType);
    }
}
