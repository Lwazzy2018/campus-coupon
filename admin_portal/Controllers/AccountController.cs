using AdminPortal.Models;
using AdminPortal.Services;
using Microsoft.AspNetCore.Authentication;
using Microsoft.AspNetCore.Authentication.Cookies;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace AdminPortal.Controllers;

/// Figma web: "Welcome Page" (login) and "Create Account".
/// Sequence Diagram 2, steps 1-8. Event administrators AND cafeteria staff
/// (Use Case Diagram: "Authenticate User <<include>> Role based access control").
[AllowAnonymous]
public class AccountController(SupabaseClient db) : Controller
{
    [HttpGet]
    public IActionResult Login(string? returnUrl = null)
    {
        if (User.Identity?.IsAuthenticated == true)
            return User.IsInRole("cafeteria") ? RedirectToAction("Index", "Cafeteria") : RedirectToAction("Index", "Dashboard");
        ViewData["ReturnUrl"] = returnUrl;
        return View(new LoginVm());
    }

    // Steps 5-8: Login(credentials) -> validate credentials -> success -> show admin dashboard
    [HttpPost, ValidateAntiForgeryToken]
    public async Task<IActionResult> Login(LoginVm vm, string? returnUrl = null)
    {
        if (!ModelState.IsValid) return View(vm);
        try
        {
            // "Staff number or email" -> email
            var email = await db.RpcAsync<string?>("admin_login_email", new { identifier = vm.Identifier });
            if (string.IsNullOrEmpty(email)) throw new SupabaseException("No staff account found with that staff number.");

            var session = await db.SignInAsync(email, vm.Password);

            // Temporarily sign in so the next calls run as this user, then check the role.
            var temp = SupabaseClient.BuildPrincipal(session, "pending", email);
            HttpContext.User = temp;
            var role = await db.RpcAsync<string?>("current_app_role");
            if (role is not ("admin" or "cafeteria"))
                throw new SupabaseException("This portal is for event administrators and cafeteria staff. Students use the mobile app.");

            var name = email;
            if (role == "admin")
                name = (await db.GetOneAsync<AdminRow>($"event_administrators?select=name&event_admin_id=eq.{session.User.Id}"))?.Name ?? email;
            else
                name = (await db.GetOneAsync<CafeteriaRow>($"cafeteria_staff?select=name&cafeteria_staff_id=eq.{session.User.Id}"))?.Name ?? email;
            if (string.IsNullOrWhiteSpace(name)) name = email;

            await HttpContext.SignInAsync(CookieAuthenticationDefaults.AuthenticationScheme,
                SupabaseClient.BuildPrincipal(session, role, name));

            if (role == "cafeteria") return RedirectToAction("Index", "Cafeteria");
            if (!string.IsNullOrEmpty(returnUrl) && Url.IsLocalUrl(returnUrl)) return Redirect(returnUrl);
            return RedirectToAction("Index", "Dashboard");
        }
        catch (SupabaseException ex)
        {
            ModelState.AddModelError("", ex.Message);
            return View(vm);
        }
    }

    [HttpGet]
    public IActionResult Register() => View(new RegisterVm());

    // Steps 1-4: Register account -> send registration data -> user created -> success message
    // Account type: Event Administrator or Cafeteria Staff (both need a @cut.ac.za email).
    [HttpPost, ValidateAntiForgeryToken]
    public async Task<IActionResult> Register(RegisterVm vm)
    {
        if (!ModelState.IsValid) return View(vm);
        try
        {
            await db.SignUpAsync(vm.Email.Trim().ToLowerInvariant(), vm.Password, new Dictionary<string, string>
            {
                ["role"] = vm.AccountType,                      // "admin" | "cafeteria"
                ["full_name"] = vm.FullName.Trim(),
                ["staff_number"] = vm.StaffNumber.Trim(),
                ["department"] = vm.AccountType == "cafeteria" ? "Cafeteria" : vm.Department ?? "",
            });
            TempData["Success"] = "Account created. Check your CUT email to confirm it, then log in.";
            return RedirectToAction(nameof(Login));
        }
        catch (SupabaseException ex)
        {
            ModelState.AddModelError("", ex.Message);
            return View(vm);
        }
    }

    [HttpPost, ValidateAntiForgeryToken]
    public async Task<IActionResult> ForgotPassword(string identifier)
    {
        try
        {
            var email = await db.RpcAsync<string?>("admin_login_email", new { identifier = identifier ?? "" });
            if (!string.IsNullOrEmpty(email)) await db.SendPasswordResetAsync(email);
        }
        catch (SupabaseException) { /* don't reveal whether the account exists */ }
        TempData["Success"] = "If that account exists, a password reset link has been sent to its email.";
        return RedirectToAction(nameof(Login));
    }

    [HttpPost, ValidateAntiForgeryToken]
    public async Task<IActionResult> Logout()
    {
        await HttpContext.SignOutAsync(CookieAuthenticationDefaults.AuthenticationScheme);
        return RedirectToAction(nameof(Login));
    }
}
