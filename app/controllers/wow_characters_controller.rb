class WowCharactersController < ApplicationController
  # Claiming a character needs no Battle.net link — that's the point. The claim
  # is an assertion, not proof, and the account page renders it as such.
  def create
    result = WowCharacters::Claim.call(
      user: current_user,
      name: params[:name], realm_slug: params[:realm], region: params[:region]
    )

    if result.ok?
      # Fill in gear, score and parses in the background so a freshly claimed
      # character isn't blank while the user is looking at it.
      WowCharacterRefreshJob.perform_later(result.character.id)
      redirect_to account_path, notice: claimed_notice(result)
    else
      redirect_to account_path, alert: result.error
    end
  end

  # Releasing a claim only ever removes the assertion. A verified character
  # belongs to the Battle.net link and is removed by unlinking that, not here.
  def destroy
    character = current_user.wow_characters.unverified.find(params[:id])
    character.destroy!
    redirect_to account_path, notice: "Released #{character.full_name}."
  end

  private

  def claimed_notice(result)
    return "#{result.character.full_name} is already yours." if result.status == :already_yours

    "Claimed #{result.character.full_name}. It's marked unverified until you link Battle.net."
  end
end
