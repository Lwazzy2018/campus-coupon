using AdminPortal.Models;
using AdminPortal.Services;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace AdminPortal.Controllers;

/// The "Search events, Participants" bar at the top of every admin page.
[Authorize(Policy = "Admin")]
public class SearchController(SupabaseClient db) : Controller
{
    public async Task<IActionResult> Index(string? q)
    {
        ViewData["Search"] = q;
        if (string.IsNullOrWhiteSpace(q)) return RedirectToAction("Index", "Dashboard");
        var s = Uri.EscapeDataString(q.Trim());
        try
        {
            var events = await db.GetAsync<EventRow>($"events?select=*,rsvp(count)&title=ilike.*{s}*&order=event_date.desc&limit=20");
            var people = await db.GetAsync<ParticipantRow>(
                $"event_participants?select=*&or=(student_name.ilike.*{s}*,student_number.ilike.*{s}*)&limit=50");
            return View((events, people));
        }
        catch (SupabaseException ex)
        {
            TempData["Error"] = ex.Message;
            return View((new List<EventRow>(), new List<ParticipantRow>()));
        }
    }
}
