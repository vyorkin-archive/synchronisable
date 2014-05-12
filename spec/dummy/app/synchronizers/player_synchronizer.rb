class PlayerSynchronizer < Synchronizable::Synchronizer
  @gateway = PlayerGateway.new

  remote_id :player_id

  mappings(
    :eman_tsrif   => :first_name,
    :eman_tsal    => :last_name,
    :yadhtrib     => :birthday,
    :pihsnezitic  => :citizenship,
    :thgieh       => :height,
    :thgiew       => :weight,
    :team         => :team_id
  )
  only :team, :eman_tsrif, :eman_tsal

  find  { |id| @gateway.find(id) }
  fetch { @gateway.fetch }
end
