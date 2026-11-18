using System.ComponentModel.DataAnnotations;

namespace AdminPortal.Models;

// ---------------------------------------------------------------------------
// Rows read from Supabase. Property names map to snake_case columns
// automatically (EventId <-> event_id), see SupabaseClient.Json.
// ---------------------------------------------------------------------------

/// ERD: EVENTS
public class EventRow
{
    public long EventId { get; set; }
    public string AdminUserId { get; set; } = "";
    public string Title { get; set; } = "";
    public string Description { get; set; } = "";
    public DateOnly EventDate { get; set; }
    public TimeOnly StartTime { get; set; }
    public TimeOnly? EndTime { get; set; }
    public string Location { get; set; } = "";
    public int PointsReward { get; set; }
    public string Category { get; set; } = "Other";
    public string? ImageUrl { get; set; }
    public string Status { get; set; } = "published";
    public List<CountRow>? Rsvp { get; set; }   // from select=*,rsvp(count)

    public int RsvpCount => Rsvp?.FirstOrDefault()?.Count ?? 0;
    public string TimeLabel => EndTime is null
        ? StartTime.ToString("HH:mm")
        : $"{StartTime.ToString("HH:mm")} - {EndTime.Value.ToString("HH:mm")}";
    public string DateLabel => EventDate.ToString("d MMMM yyyy");

    /// Badge on the View Event screen ("Upcoming")
    public string Badge =>
        Status == "draft" ? "Draft" :
        Status == "closed" ? "Closed" :
        EventDate < DateOnly.FromDateTime(DateTime.Today) ? "Past" : "Upcoming";
}

public class CountRow { public int Count { get; set; } }

/// View event_participants (RSVP + STUDENTS + ATTENDANCE)
public class ParticipantRow
{
    public long RsvpId { get; set; }
    public long EventId { get; set; }
    public string EventTitle { get; set; } = "";
    public string StudentName { get; set; } = "";
    public string StudentNumber { get; set; } = "";
    public string Status { get; set; } = "registered";   // registered | attended | not_attended
}

public class DashboardStats
{
    public long TotalEvents { get; set; }
    public long ActiveEvents { get; set; }
    public long PointsRedeemed { get; set; }
    public long TotalParticipants { get; set; }
}

/// AUDIT_LOG -> "Recent Activity"
public class ActivityRow
{
    public string Title { get; set; } = "";
    public string Detail { get; set; } = "";
    public DateTimeOffset CreatedAt { get; set; }

    public string Ago
    {
        get
        {
            var d = DateTimeOffset.UtcNow - CreatedAt;
            if (d.TotalMinutes < 1) return "just now";
            if (d.TotalMinutes < 60) return $"{(int)d.TotalMinutes} minutes ago";
            if (d.TotalHours < 24) return $"{(int)d.TotalHours} hours ago";
            return $"{(int)d.TotalDays} days ago";
        }
    }
}

/// ERD: EVENT ADMINISTRATOR
public class AdminRow
{
    public string EventAdminId { get; set; } = "";
    public string Name { get; set; } = "";
    public string Email { get; set; } = "";
    public string? StaffNumber { get; set; }
    public string? Department { get; set; }
    public string? Phone { get; set; }
}

public class NotificationPrefs
{
    public bool NewEventRegistration { get; set; }
    public bool AttendanceUpdates { get; set; }
    public bool PointsRedemptions { get; set; }
    public bool SystemAnnouncements { get; set; }
    public bool WeeklyReports { get; set; }
}

/// ERD: REDEMPTIONS (+ coupon and student names)
public class RedemptionRow
{
    public long RedemptionId { get; set; }
    public string RedemptionCode { get; set; } = "";
    public string Status { get; set; } = "";
    public DateTimeOffset CreatedAt { get; set; }
    public DateTimeOffset? AcceptedAt { get; set; }
    public NameRow? Coupons { get; set; }
    public StudentNameRow? Students { get; set; }
}
public class NameRow { public string Title { get; set; } = ""; public int PointsCost { get; set; } }
public class StudentNameRow { public string Name { get; set; } = ""; public string StudentNumber { get; set; } = ""; }

public class AcceptResult
{
    public string CouponTitle { get; set; } = "";
    public string StudentName { get; set; } = "";
    public string StudentNumber { get; set; } = "";
    public int RefundedPoints { get; set; }   // only set by cafeteria_reject
}

/// ERD: CAFETERIA STAFF
public class CafeteriaRow
{
    public string CafeteriaStaffId { get; set; } = "";
    public string Name { get; set; } = "";
    public string Email { get; set; } = "";
    public string? StaffNumber { get; set; }
}

/// One row from list_redemptions() (06_cafeteria_staff.sql):
/// REDEMPTIONS + coupon + student + the cafeteria staff member who processed it.
public class RedemptionRecord
{
    public long RedemptionId { get; set; }
    public string RedemptionCode { get; set; } = "";
    public string Status { get; set; } = "issued";        // issued | accepted | rejected
    public string CouponTitle { get; set; } = "";
    public int PointsCost { get; set; }
    public DateOnly ValidUntil { get; set; }
    public string StudentName { get; set; } = "";
    public string StudentNumber { get; set; } = "";
    public DateTimeOffset CreatedAt { get; set; }
    public DateTimeOffset? ProcessedAt { get; set; }
    public string? ProcessedBy { get; set; }
    public string? RejectReason { get; set; }

    public bool IsExpired => ValidUntil < DateOnly.FromDateTime(DateTime.Today);

    public string StatusLabel => Status switch
    {
        "accepted" => "Approved",
        "rejected" => "Rejected",
        _ => "Pending",
    };

    /// CSS pill class (site.css): green / red / blue
    public string StatusPill => Status switch
    {
        "accepted" => "attended",
        "rejected" => "absent",
        _ => "registered",
    };

    public string WaitingFor
    {
        get
        {
            var d = DateTimeOffset.UtcNow - CreatedAt;
            if (d.TotalMinutes < 1) return "just now";
            if (d.TotalMinutes < 60) return $"{(int)d.TotalMinutes} min ago";
            if (d.TotalHours < 24) return $"{(int)d.TotalHours} h ago";
            return $"{(int)d.TotalDays} days ago";
        }
    }
}

/// cafeteria_stats(): numbers across the top of the Cafeteria pages
public class CafeteriaStats
{
    public long Pending { get; set; }
    public long ApprovedToday { get; set; }
    public long RejectedToday { get; set; }
    public long ApprovedTotal { get; set; }
    public long RejectedTotal { get; set; }
    public long PointsApprovedToday { get; set; }
}

// ---------------------------------------------------------------------------
// Form view models (server-side validation = FR-021)
// ---------------------------------------------------------------------------

public static class Lists
{
    public static readonly string[] Departments =
    {
        "Student Development Office (SDO)", "Student Affairs", "Information Technology",
        "Faculty of Engineering", "Faculty of Management Sciences", "Sport", "Cafeteria", "Other",
    };
    public static readonly string[] Categories = { "Career", "Other" };

    /// Why cafeteria staff did not give the meal (points are refunded).
    public static readonly string[] RejectReasons =
    {
        "Student card not presented", "Student details do not match", "Item not available",
        "Coupon expired", "Code already used / screenshot", "Other",
    };

    /// Who can register in the web portal (value = role sent to Supabase).
    public static readonly Dictionary<string, string> AccountTypes = new()
    {
        ["admin"] = "Event Administrator",
        ["cafeteria"] = "Cafeteria Staff",
    };
}

public class LoginVm
{
    [Required(ErrorMessage = "Enter your staff number or email")]
    public string Identifier { get; set; } = "";

    [Required(ErrorMessage = "Enter your password"), DataType(DataType.Password)]
    public string Password { get; set; } = "";
}

public class RegisterVm : IValidatableObject
{
    [Required(ErrorMessage = "Select an account type")]
    [Display(Name = "Account type")]
    public string AccountType { get; set; } = "admin";

    [Required, StringLength(100, MinimumLength = 3)]
    [Display(Name = "Full Name")]
    public string FullName { get; set; } = "";

    [Required, EmailAddress]
    [RegularExpression(@"^[^@\s]+@cut\.ac\.za$", ErrorMessage = "Use your CUT staff email (e.g. admin@cut.ac.za)")]
    public string Email { get; set; } = "";

    [Required, RegularExpression(@"^\d{4,10}$", ErrorMessage = "Staff number must be digits only")]
    [Display(Name = "Staff number")]
    public string StaffNumber { get; set; } = "";

    // Required for Event Administrators only (see Validate)
    public string? Department { get; set; }

    [Required, MinLength(8, ErrorMessage = "Use at least 8 characters"), DataType(DataType.Password)]
    public string Password { get; set; } = "";

    [Required, Compare(nameof(Password), ErrorMessage = "Passwords do not match"), DataType(DataType.Password)]
    [Display(Name = "Confirm Password")]
    public string ConfirmPassword { get; set; } = "";

    public IEnumerable<ValidationResult> Validate(ValidationContext context)
    {
        if (!Lists.AccountTypes.ContainsKey(AccountType))
            yield return new ValidationResult("Select an account type", new[] { nameof(AccountType) });
        if (AccountType == "admin" && string.IsNullOrWhiteSpace(Department))
            yield return new ValidationResult("Select a department", new[] { nameof(Department) });
    }
}

public class EventFormVm : IValidatableObject
{
    public long? EventId { get; set; }

    [Required(ErrorMessage = "Enter the event title"), StringLength(120)]
    [Display(Name = "Event Title")]
    public string Title { get; set; } = "";

    [Required(ErrorMessage = "Enter an event description"), StringLength(2000)]
    public string Description { get; set; } = "";

    [Required(ErrorMessage = "Select a date")]
    public DateOnly? EventDate { get; set; }

    [Required(ErrorMessage = "Select a start time")]
    [Display(Name = "Start time")]
    public TimeOnly? StartTime { get; set; }

    [Display(Name = "End time")]
    public TimeOnly? EndTime { get; set; }

    [Required(ErrorMessage = "Enter the location"), StringLength(150)]
    public string Location { get; set; } = "";

    [Range(0, 1000, ErrorMessage = "Points must be between 0 and 1000")]
    [Display(Name = "Points Reward")]
    public int PointsReward { get; set; } = 50;

    [Required(ErrorMessage = "Select a category")]
    public string Category { get; set; } = "Other";

    [Display(Name = "Status")]
    public string Status { get; set; } = "published";

    public string? ImageUrl { get; set; }

    [Display(Name = "Event poster (optional)")]
    public IFormFile? Poster { get; set; }

    public IEnumerable<ValidationResult> Validate(ValidationContext context)
    {
        if (EventId is null && EventDate < DateOnly.FromDateTime(DateTime.Today))
            yield return new ValidationResult("The event date cannot be in the past", new[] { nameof(EventDate) });
        if (EndTime.HasValue && StartTime.HasValue && EndTime <= StartTime)
            yield return new ValidationResult("End time must be after the start time", new[] { nameof(EndTime) });
        if (Poster is { Length: > 5_000_000 })
            yield return new ValidationResult("Poster must be smaller than 5 MB", new[] { nameof(Poster) });
    }
}

public class ProfileVm
{
    [Required, StringLength(100, MinimumLength = 3)]
    [Display(Name = "Full Name")]
    public string Name { get; set; } = "";

    [Display(Name = "Staff Email")]
    public string Email { get; set; } = "";

    [RegularExpression(@"^\d{4,10}$", ErrorMessage = "Staff number must be digits only")]
    [Display(Name = "Staff Number")]
    public string? StaffNumber { get; set; }

    public string? Department { get; set; }

    [RegularExpression(@"^0\d{9}$", ErrorMessage = "Phone number must be 10 digits starting with 0")]
    [Display(Name = "Phone numbers")]
    public string? Phone { get; set; }
}

// ---------------------------------------------------------------------------
// Meals / Coupons page (07_meals.sql)
// ---------------------------------------------------------------------------

/// ERD: COUPONS (+ how many times it was redeemed, from select=*,redemptions(count))
public class CouponRow
{
    public long CouponId { get; set; }
    public string Title { get; set; } = "";
    public string Category { get; set; } = "Food";
    public int PointsCost { get; set; }
    public DateOnly ValidUntil { get; set; }
    public string Location { get; set; } = "";
    public string Terms { get; set; } = "";
    public string? ImageUrl { get; set; }
    public bool IsActive { get; set; } = true;
    public List<CountRow>? Redemptions { get; set; }

    public int RedeemedCount => Redemptions?.FirstOrDefault()?.Count ?? 0;
    public bool IsExpired => ValidUntil < DateOnly.FromDateTime(DateTime.Today);

    /// What students see: only Available coupons appear in the app.
    public string StatusLabel => !IsActive ? "Switched off" : IsExpired ? "Expired" : "Available";
    public string StatusPill => !IsActive ? "absent" : IsExpired ? "absent" : "attended";
}

public class CouponFormVm : IValidatableObject
{
    public long? CouponId { get; set; }

    [Required(ErrorMessage = "Enter the meal / coupon name"), StringLength(80)]
    [Display(Name = "Name")]
    public string Title { get; set; } = "";

    [Required]
    public string Category { get; set; } = "Food";

    [Range(1, 10000, ErrorMessage = "Points must be between 1 and 10 000")]
    [Display(Name = "Points needed")]
    public int PointsCost { get; set; } = 250;

    [Required(ErrorMessage = "Select the last day it can be redeemed")]
    [Display(Name = "Valid until")]
    public DateOnly? ValidUntil { get; set; }

    [Required(ErrorMessage = "Enter where students collect it"), StringLength(150)]
    public string Location { get; set; } = "CUT Welkom Campus Cafeteria";

    [StringLength(1000)]
    [Display(Name = "Terms & Conditions")]
    public string? Terms { get; set; } = "-Valid at CUT WELKOM ONLY\n-Present student card\n-Not valid with other promotions";

    [Display(Name = "Available to students")]
    public bool IsActive { get; set; } = true;

    public string? ImageUrl { get; set; }

    [Display(Name = "Photo (optional)")]
    public IFormFile? Photo { get; set; }

    public IEnumerable<ValidationResult> Validate(ValidationContext context)
    {
        if (Category is not ("Food" or "Retail"))
            yield return new ValidationResult("Select Food or Retail", new[] { nameof(Category) });
        if (CouponId is null && ValidUntil < DateOnly.FromDateTime(DateTime.Today))
            yield return new ValidationResult("The date cannot be in the past", new[] { nameof(ValidUntil) });
        if (Photo is { Length: > 5_000_000 })
            yield return new ValidationResult("Photo must be smaller than 5 MB", new[] { nameof(Photo) });
    }
}
