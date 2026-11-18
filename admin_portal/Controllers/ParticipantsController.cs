using AdminPortal.Models;
using AdminPortal.Services;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace AdminPortal.Controllers;

/// Figma web: "Participants" (All / Registered / Attended).
/// Use cases: View RSVP list, Record attendance <<include>> Verify attendance
///            <<extend>> Credit reward points.   Sequence Diagram 2, steps 17-22.
[Authorize(Policy = "Admin")]
public class ParticipantsController(SupabaseClient db) : Controller
{
    public async Task<IActionResult> Index(long? eventId, string filter = "All", string? search = null)
    {
        ViewData["Active"] = "Participants";
        var q = "event_participants?select=*&order=event_id.desc,student_name";
        if (eventId.HasValue) q += $"&event_id=eq.{eventId}";
        if (filter == "Registered") q += "&status=eq.registered";
        if (filter == "Attended") q += "&status=eq.attended";
        if (!string.IsNullOrWhiteSpace(search))
        {
            var s = Uri.EscapeDataString(search.Trim());
            q += $"&or=(student_name.ilike.*{s}*,student_number.ilike.*{s}*)";
        }

        try
        {
            var rows = await db.GetAsync<ParticipantRow>(q);
            var events = await db.GetAsync<EventRow>("events?select=event_id,title,event_date&order=event_date.desc");
            ViewData["Events"] = events;
            ViewData["EventId"] = eventId;
            ViewData["Filter"] = filter;
            ViewData["Search"] = search;
            return View(rows);
        }
        catch (SupabaseException ex)
        {
            TempData["Error"] = ex.Message;
            ViewData["Events"] = new List<EventRow>();
            return View(new List<ParticipantRow>());
        }
    }

    // Steps 17-22: Select student -> click Attended -> update attendance -> update wallet -> success
    [HttpPost, ValidateAntiForgeryToken]
    public async Task<IActionResult> MarkAttendance(long rsvpId, bool attended, string? returnUrl)
    {
        try
        {
            var credited = await db.RpcAsync<int>("record_attendance", new { p_rsvp_id = rsvpId, p_attended = attended });
            TempData["Success"] = attended
                ? (credited > 0 ? $"Attendance approved. {credited} points credited to the student's wallet."
                                : "Attendance approved (points were already credited earlier).")
                : "Marked as not attended. No points awarded.";
        }
        catch (SupabaseException ex) { TempData["Error"] = ex.Message; }

        if (!string.IsNullOrEmpty(returnUrl) && Url.IsLocalUrl(returnUrl)) return Redirect(returnUrl);
        return RedirectToAction(nameof(Index));
    }
}
