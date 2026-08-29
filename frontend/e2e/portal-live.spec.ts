import { expect, test } from "@playwright/test";

test("authenticated devops user can view images and request a desktop", async ({ page }) => {
  const username = process.env.VDIFORGE_E2E_USERNAME;
  const password = process.env.VDIFORGE_E2E_PASSWORD;

  test.skip(!username || !password, "Set VDIFORGE_E2E_USERNAME and VDIFORGE_E2E_PASSWORD to run the live portal flow.");

  await page.goto("/");
  await page.getByRole("button", { name: "Sign in" }).click();

  await page.getByLabel(/username|email/i).fill(username!);
  await page.getByLabel(/password/i).fill(password!);
  await page.getByRole("button", { name: /sign in/i }).click();

  await expect(page.getByRole("heading", { name: "Dashboard" })).toBeVisible();
  await page.getByRole("button", { name: "Images" }).click();
  await expect(page.getByText("Ubuntu DevOps")).toBeVisible();

  if (process.env.VDIFORGE_E2E_LAUNCH === "true") {
    await page.getByRole("button", { name: "Launch Ubuntu DevOps" }).click();
    await page.getByLabel("Desktop name").fill(`Portal E2E ${Date.now()}`);
    await page.getByRole("button", { name: "Launch Desktop" }).click();
    await expect(page.getByRole("heading", { name: "My Desktops" })).toBeVisible();
    await expect(page.getByText(/Request received|Creating desktop|Starting Ubuntu|Ready/)).toBeVisible();
  }
});
