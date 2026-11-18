using System.Globalization;
using System.Text;
using AdminPortal.Models;
using AdminPortal.Services;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace AdminPortal.Controllers;

/// Third user from the Use Case Diagram: CAFETERIA STAFF.
/// Use case "Accept coupon redemption":
///   Current Redemptions -> check the student's code -> Approve (give the meal)
///                                                   -> Reject  (no meal, points refunded)
/// SRS "maintain or support redemption records" -> Redemption History (+ CSV download).
/// All rules (who may approve, no double use, refunds) live in 06_cafeteria_staff.sql.
[Authorize(Policy = "Cafeteria")]
public class CafeteriaController(SupabaseClient db) : Controller
{
    // ------------------------------------------------------------ Current
    /// Waiting coupons, oldest first (a queue). ?q= finds one code / student.
    public async Task<IActionResult> Index(string? q)
    {
        ViewData["Active"] = "CafeteriaCurrent";
        ViewData["Title"] = "Current Redemptions";
        ViewData["Query"] = q;
        try
        {
            var rows = await db.RpcAsync<List<RedemptionRecord>>("list_redemptions", new
            {
                p_status = "issued",
                p_search = string.IsNullOrWhiteSpace(q) ? null : q.Trim(),
            });
            ViewData["Stats"] = await StatsAsync();

            // Typed a code that is not waiting any more? Say what happened to it.
            if (!string.IsNullOrWhiteSpace(q) && rows.Count == 0)
            {
                var done = (await db.RpcAsync<List<RedemptionRecord>>("list_redemptions", new { p_search = q.Trim(), p_limit = 1 }))
                    .FirstOrDefault();
                if (done is not null)
                    TempData["Error"] = done.Status == "accepted"
                        ? $"{done.RedemptionCode} was already APPROVED on {Local(done.ProcessedAt)} by {done.ProcessedBy}. Do not give another meal."
                        : $"{done.RedemptionCode} was REJECTED on {Local(done.ProcessedAt)} ({done.RejectReason}). The points were refunded.";
                else
                    TempData["Error"] = $"No coupon found for \"{q.Trim()}\". Check the code on the student's phone.";
            }
            return View(rows);
        }
        catch (SupabaseException ex)
        {
            TempData["Error"] = ex.Message;
            ViewData["Stats"] = new CafeteriaStats();
            return View(new List<RedemptionRecord>());
        }
    }

    /// Approve: the coupon is valid -> hand over the meal.
    [HttpPost, ValidateAntiForgeryToken]
    public async Task<IActionResult> Approve(long id, string? returnUrl)
    {
        try
        {
            var r = (await db.RpcAsync<List<AcceptResult>>("cafeteria_approve", new { p_redemption_id = id })).First();
            TempData["Success"] = $"✔ Approved: give {r.CouponTitle} to {r.StudentName} ({r.StudentNumber}).";
        }
        catch (SupabaseException ex) { TempData["Error"] = ex.Message; }
        return Back(returnUrl);
    }

    /// Reject: no meal. The student's points are refunded to their wallet.
    [HttpPost, ValidateAntiForgeryToken]
    public async Task<IActionResult> Reject(long id, string? reason, string? returnUrl)
    {
        if (string.IsNullOrWhiteSpace(reason) || !Lists.RejectReasons.Contains(reason))
        {
            TempData["Error"] = "Select a reason before rejecting the coupon.";
            return Back(returnUrl);
        }
        try
        {
            var r = (await db.RpcAsync<List<AcceptResult>>("cafeteria_reject", new { p_redemption_id = id, p_reason = reason })).First();
            TempData["Success"] = $"✖ Rejected: do NOT give {r.CouponTitle} to {r.StudentName} ({r.StudentNumber}). " +
                                  $"{r.RefundedPoints} points were returned to the student's wallet.";
        }
        catch (SupabaseException ex) { TempData["Error"] = ex.Message; }
        return Back(returnUrl);
    }

    // ------------------------------------------------------------ History
    /// Records of all redemptions: status tabs, search, date range.
    public async Task<IActionResult> History(string status = "All", string? q = null, DateOnly? from = null, DateOnly? to = null)
    {
        ViewData["Active"] = "CafeteriaHistory";
        ViewData["Title"] = "Redemption History";
        ViewData["Status"] = status;
        ViewData["Query"] = q;
        ViewData["From"] = from?.ToString("yyyy-MM-dd");
        ViewData["To"] = to?.ToString("yyyy-MM-dd");
        try
        {
            var rows = await LoadHistoryAsync(status, q, from, to);
            ViewData["Stats"] = await StatsAsync();
            return View(rows);
        }
        catch (SupabaseException ex)
        {
            TempData["Error"] = ex.Message;
            ViewData["Stats"] = new CafeteriaStats();
            return View(new List<RedemptionRecord>());
        }
    }

    /// Same filters as History, as a spreadsheet-friendly CSV file.
    public async Task<IActionResult> Export(string status = "All", string? q = null, DateOnly? from = null, DateOnly? to = null)
    {
        try
        {
            var rows = await LoadHistoryAsync(status, q, from, to, limit: 1000);
            var sb = new StringBuilder();
            sb.AppendLine("Redeemed,Code,Coupon,Points,Student,Student number,Status,Processed,Processed by,Reason");
            foreach (var r in rows)
            {
                sb.AppendLine(string.Join(",",
                    Csv(Local(r.CreatedAt)), Csv(r.RedemptionCode), Csv(r.CouponTitle),
                    r.PointsCost.ToString(CultureInfo.InvariantCulture), Csv(r.StudentName), Csv(r.StudentNumber),
                    Csv(r.StatusLabel), Csv(Local(r.ProcessedAt)), Csv(r.ProcessedBy), Csv(r.RejectReason)));
            }
            // UTF-8 with BOM so Excel shows names correctly
            var bytes = Encoding.UTF8.GetPreamble().Concat(Encoding.UTF8.GetBytes(sb.ToString())).ToArray();
            return File(bytes, "text/csv", $"redemptions-{DateTime.Now:yyyy-MM-dd}.csv");
        }
        catch (SupabaseException ex)
        {
            TempData["Error"] = ex.Message;
            return RedirectToAction(nameof(History), new { status, q, from, to });
        }
    }

    // ------------------------------------------------------------ Helpers
    private Task<List<RedemptionRecord>> LoadHistoryAsync(string status, string? q, DateOnly? from, DateOnly? to, int limit = 300) =>
        db.RpcAsync<List<RedemptionRecord>>("list_redemptions", new
        {
            p_status = status switch { "Approved" => "accepted", "Rejected" => "rejected", "Pending" => "issued", _ => null },
            p_search = string.IsNullOrWhiteSpace(q) ? null : q.Trim(),
            p_from = from?.ToString("yyyy-MM-dd"),
            p_to = to?.ToString("yyyy-MM-dd"),
            p_limit = limit,
        });

    private async Task<CafeteriaStats> StatsAsync() =>
        (await db.RpcAsync<List<CafeteriaStats>>("cafeteria_stats")).FirstOrDefault() ?? new CafeteriaStats();

    private IActionResult Back(string? returnUrl) =>
        !string.IsNullOrEmpty(returnUrl) && Url.IsLocalUrl(returnUrl) ? Redirect(returnUrl) : RedirectToAction(nameof(Index));

    private static string Local(DateTimeOffset? t) => t?.ToLocalTime().ToString("d MMM yyyy HH:mm") ?? "";

    private static string Csv(string? v)
    {
        v ??= "";
        return v.IndexOfAny(new[] { ',', '"', '\n', '\r' }) >= 0 ? "\"" + v.Replace("\"", "\"\"") + "\"" : v;
    }
}
